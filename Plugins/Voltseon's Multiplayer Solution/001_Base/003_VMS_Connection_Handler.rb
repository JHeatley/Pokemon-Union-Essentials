module VMS
  require "socket"
  require "zlib"

  #---------------------------------------------------------------------------
  # Stable follower packet keys
  #---------------------------------------------------------------------------
  PACKET_KEYS[:follower_active]    ||= 31
  PACKET_KEYS[:follower_graphic]   ||= 32
  PACKET_KEYS[:follower_direction] ||= 33

  REVERSE_KEYS[31] = :follower_active
  REVERSE_KEYS[32] = :follower_graphic
  REVERSE_KEYS[33] = :follower_direction

  # Usage: VMS.join(id #<Integer>) (connects to the server with the specified ID)
  def self.join(id = -1)
    if id == -1
      VMS.log("No ID specified", true)
      return
    end
    if !$game_temp.vms[:socket].nil?
      VMS.log("Already connected to a server")
      return
    end

    host = $game_temp.vms[:using_external_server] ? VMS::EXTERNALHOST : VMS.target_host
    port = $game_temp.vms[:using_external_server] ? VMS::EXTERNALPORT : VMS::PORT

    begin
      if VMS::USE_TCP
        socket = TCPSocket.new(host, port)
      else
        socket = UDPSocket.new
        socket.connect(host, port)
      end
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET
      VMS.log("Server is not active", true)
    rescue => e
      VMS.log("Failed to connect to server: #{e}", true)
    ensure
      return if socket.nil?
    end

    $game_temp.vms[:cluster] = id
    player_data = VMS.generate_player_data
    $game_temp.vms[:socket] = socket

    VMS.send_message(["connect", player_data])
    VMS.log("Connected to server")
  end

  # Usage: VMS.leave (disconnects from the server)
  def self.leave(show_message = true)
    VMS::IntegratedServer.stop if !$game_temp.vms[:using_external_server] && defined?(VMS::IntegratedServer)

    if $game_temp.vms[:socket].nil?
      VMS.log("Not connected to a server") if show_message
      return
    end

    VMS.clear_events
    VMS.send_message(["disconnect", VMS.generate_player_data])

    $game_temp.vms[:socket].close

    System.set_window_title(System.game_title) if VMS::SHOW_PING
    $game_temp.vms[:socket] = nil
    $game_temp.vms[:cluster] = -1
    $game_temp.vms[:ping_log] = []
    $game_temp.vms[:time_since_last_message] = 0
    $game_temp.vms[:ping_stamp] = 0
    $game_temp.vms[:players] = {}
    $game_temp.vms[:online_variables] = {}
    $game_temp.vms[:using_external_server] = false

    VMS.log("Disconnected from server") if show_message
    VMS.message(VMS::DISCONNECTED_MESSAGE) if !(VMS::DISCONNECTED_MESSAGE.nil? || VMS::DISCONNECTED_MESSAGE == "" || !show_message)
  end

  # Usage: VMS.update (sends and receives data from the server)
  def self.update
    return if $game_temp.vms[:socket].nil?

    if VMS::SHOW_PING
      $game_temp.vms[:ping_log].push((VMS.ping * 500).round)
      $game_temp.vms[:ping_log].shift if $game_temp.vms[:ping_log].size > 50
      ping = [$game_temp.vms[:ping_log].sum / $game_temp.vms[:ping_log].size, 0].max
      cluster_id = VMS.get_cluster_id
      cluster_str = cluster_id && cluster_id >= 0 ? " [Cluster #{cluster_id}]" : ""
      System.set_window_title(System.game_title + (ping != -1 ? " (#{ping}ms)" : "") + cluster_str)
    end

    begin
      if VMS::TICK_RATE == 0 || Graphics.frame_count % (60 / VMS::TICK_RATE) == 0
        send_data = VMS.generate_player_data
        own_player = VMS.get_self

        update_data = if own_player.nil?
          send_data
        else
          send_data.reject do |key, value|
            sym = VMS::REVERSE_KEYS[key]
            next false if sym.nil?

            sym != :state &&
            sym != :cluster_id &&
            sym != :id &&
            sym != :heartbeat &&
            (
              (!value.is_a?(Array) && own_player.instance_variable_get("@#{sym}") == value) ||
              (value.is_a?(Array) && VMS.array_compare(own_player.instance_variable_get("@#{sym}"), value))
            )
          end
        end

        VMS.send_message(["update", update_data])
      end

      data = $game_temp.vms[:socket].read_nonblock(65536, exception: false)

      if data == :wait_readable || data == :wait_writable || data.nil?
        $game_temp.vms[:time_since_last_message] += Graphics.delta
        VMS.leave if $game_temp.vms[:time_since_last_message] > VMS::TIMEOUT_SECONDS
        return
      end

      $game_temp.vms[:time_since_last_message] = 0
      data = Marshal.load(Zlib::Inflate.inflate(data))

      if data.is_a?(Symbol)
        if [:disconnect, :disconnect_full].include?(data)
          suffix = data == :disconnect_full ? " (server full)" : ""
          VMS.log("Disconnected from server#{suffix}")
          VMS.leave(false)
          VMS.message(data == :disconnect_full ? VMS::CLUSTER_FULL_MESSAGE : VMS::SERVER_DISCONNECT_MESSAGE) if !(VMS::DISCONNECTED_MESSAGE.nil? || VMS::DISCONNECTED_MESSAGE == "")
          return
        elsif data == :disconnect_wrong_game
          VMS.log("Disconnected from server (wrong game)", true)
          VMS.leave(false)
          VMS.message(VMS::DIFFERENT_GAME_MESSAGE) if !(VMS::DISCONNECTED_MESSAGE.nil? || VMS::DISCONNECTED_MESSAGE == "")
          return
        elsif data == :disconnect_wrong_version
          VMS.log("Disconnected from server (wrong version)", true)
          VMS.leave(false)
          VMS.message(VMS::DIFFERENT_VERSION_MESSAGE) if !(VMS::DISCONNECTED_MESSAGE.nil? || VMS::DISCONNECTED_MESSAGE == "")
          return
        end
      end

      if data[0] == :disconnect_player
        id = data[1]
        player = VMS.get_player(id)
        return if player.nil?
        VMS.log("Player #{player.name} (#{id}) has disconnected from the server")
        Rf.delete_event(player.rf_event) if VMS.event_deletion_possible?(player)
        VMS.delete_follower_event(player)
        $game_temp.vms[:players].delete(id)
        return
      end

      VMS.process(data)

    rescue Errno::ECONNREFUSED, Errno::ECONNRESET
      VMS.log("Server is not active", true)
      VMS.leave(false)
      VMS.message(VMS::SERVER_INACTIVE_MESSAGE) if !(VMS::DISCONNECTED_MESSAGE.nil? || VMS::DISCONNECTED_MESSAGE == "")
      return
    rescue => e
      VMS.log("Failed to communicate with server: #{e}", true)
      VMS.leave
      return
    end

    VMS.get_players.each do |player|
      next if player.id == $player.id
      VMS.check_timeout(player)
      VMS.check_interaction(player) if $game_temp.vms[:state][0] == :idle && VMS.interaction_possible?
    end
  end

  #---------------------------------------------------------------------------
  # Follower helper methods
  #---------------------------------------------------------------------------

  def self.local_follower_event
    return nil if !defined?(FollowingPkmn)
    return nil if !FollowingPkmn.respond_to?(:get_event)
    ev = FollowingPkmn.get_event
    return nil if ev.nil?
    return nil if ev.erased?
    return nil if ev.character_name.nil? || ev.character_name.empty?
    return ev
  rescue
    return nil
  end

  def self.create_follower_event(map_id, id)
    rf_event = Rf.create_event(map_id) do |event|
      event.x = 0
      event.y = 0
      event.name = "vms_follower_#{id}"
      page = RPG::Event::Page.new
      page.list.clear
      page.trigger = 0
      page.through = true
      page.walk_anime = true
      page.step_anime = true
      page.direction_fix = false
      event.pages = [page]
    end
    rf_event[:event].name = "vms_follower_#{id}"
    return rf_event
  end

  def self.delete_follower_event(player)
    return if player.nil?
    return if !player.respond_to?(:follower_rf_event)
    return if player.follower_rf_event.nil?
    begin
      Rf.delete_event(player.follower_rf_event)
    rescue
    end
    player.follower_rf_event = nil
  end

  def self.remote_follower_coords(player)
    case player.direction
    when 2 then [player.x,     player.y - 1]
    when 4 then [player.x + 1, player.y    ]
    when 6 then [player.x - 1, player.y    ]
    when 8 then [player.x,     player.y + 1]
    else        [player.x,     player.y + 1]
    end
  end

  def self.handle_follower(player)
    return if player.nil?
    return unless player.respond_to?(:follower_active)
    return unless $game_map

    connected = $map_factory.areConnected?(player.map_id, $game_map.map_id)
    active    = player.follower_active
    graphic   = player.follower_graphic

    if !connected || !active || graphic.nil? || graphic.empty?
      VMS.delete_follower_event(player)
      return
    end

    if player.respond_to?(:follower_rf_event)
      if player.follower_rf_event.nil? || player.follower_rf_event[:event].erased?
        player.follower_rf_event = VMS.create_follower_event(player.map_id, player.id)
      elsif player.follower_rf_event[:event].map_id != player.map_id
        VMS.delete_follower_event(player)
        player.follower_rf_event = VMS.create_follower_event(player.map_id, player.id)
      end
    else
      return
    end

    return if player.follower_rf_event.nil?

    ev = player.follower_rf_event[:event]
    fx, fy = VMS.remote_follower_coords(player)

    ev.x = fx
    ev.y = fy
    ev.direction = player.follower_direction || player.direction
    ev.character_name = player.follower_graphic
    ev.opacity = 255
    ev.through = true
    ev.step_anime = true if ev.respond_to?(:step_anime=)
    ev.walk_anime = true if ev.respond_to?(:walk_anime=)

    ev.calculate_bush_depth if ev.respond_to?(:calculate_bush_depth)
    ev.refresh if ev.respond_to?(:refresh)
  end

  # Usage: VMS.process(data #<Hash>) (processes data received from the server)
  def self.process(data)
    VMS.sync_seed if VMS::SEED_SYNC && $game_temp.vms[:battle_player].nil?

    data.each do |pl|
      if pl[0] == :online_variables
        $game_temp.vms[:online_variables] = pl[1]
        next
      end

      id_key = VMS::PACKET_KEYS[:id]
      hb_key = VMS::PACKET_KEYS[:heartbeat]
      id = pl[id_key]
      player = $game_temp.vms[:players][id]
      is_self = id == $player.id

      if player.nil?
        $game_temp.vms[:players][id] = VMS::Player.new(id, "", 0)
        player = $game_temp.vms[:players][id]
      end

      $game_temp.vms[:ping_stamp] = pl[hb_key] if is_self

      new_packet = pl[hb_key] <= player.heartbeat - VMS::ADDED_DELAY
      next if !VMS::HANDLE_MORE_PACKETS && new_packet

      player.update(pl)
      player.is_new = new_packet

      next unless VMS::SHOW_SELF if is_self

      if player.rf_event.nil? || player.rf_event[:event].erased?
        if $map_factory.areConnected?(player.map_id, $game_map.map_id)
          player.rf_event = VMS.create_event(player.map_id, id)
        end
      elsif $map_factory.areConnected?(player.map_id, $game_map.map_id)
        if player.rf_event[:event].map_id != player.map_id
          Rf.delete_event(player.rf_event) if VMS.event_deletion_possible?(player)
          player.rf_event = VMS.create_event(player.map_id, id)
        end
      else
        Rf.delete_event(player.rf_event) if VMS.event_deletion_possible?(player)
        player.rf_event = nil
      end

      VMS.handle_player(player)
      VMS.handle_follower(player)
    end
  end

  # Usage: VMS.clear_events (deletes all player events)
  def self.clear_events
    VMS.get_players.each do |player|
      next unless VMS.event_deletion_possible?(player)
      Rf.delete_event(player.rf_event)
      player.rf_event = nil
      VMS.delete_follower_event(player)
    end
  end

  # Usage: VMS.clean_up_events (deletes all player events that are no longer necessary)
  def self.clean_up_events
    return unless $game_map

    $game_map.events.each_value do |event|
      next if event.nil?
      next if event.erased?
      next unless event.name

      if event.name.include?("vms_player")
        id = (event.name.gsub("vms_player_", "")).to_i
        player = VMS.get_player(id)
        if player.nil? || !$map_factory.areConnected?(player.map_id, $game_map.map_id)
          event.character_name = ""
          event.through = true
          event.erase
        end
      elsif event.name.include?("vms_follower")
        id = (event.name.gsub("vms_follower_", "")).to_i
        player = VMS.get_player(id)
        if player.nil? || !$map_factory.areConnected?(player.map_id, $game_map.map_id)
          event.character_name = ""
          event.through = true
          event.erase
        end
      end
    end
  end

  # Usage: VMS.send_message(message #<String>) (sends a message to the server)
  def self.send_message(message)
    if $game_temp.vms[:socket].nil?
      VMS.log("Not connected to a server")
      return
    end

    message = Zlib::Deflate.deflate(Marshal.dump(message), Zlib::BEST_SPEED)
    $game_temp.vms[:socket].send(message, 0)
  end

  # Usage: VMS.generate_player_data (generates a hash of the player's data)
  def self.generate_player_data
    party = []
    $player.party.each do |pkmn|
      party.push(VMS.hash_pokemon(pkmn))
    end

    follower_event = VMS.local_follower_event

    data = {}
    data[VMS::PACKET_KEYS[:cluster_id]]       = $game_temp.vms[:cluster] || -1
    data[VMS::PACKET_KEYS[:id]]               = $player.id
    data[VMS::PACKET_KEYS[:heartbeat]]        = Time.now
    data[VMS::PACKET_KEYS[:game_name]]        = System.game_title
    data[VMS::PACKET_KEYS[:game_version]]     = Settings::GAME_VERSION
    data[VMS::PACKET_KEYS[:online_variables]] = $game_temp.vms[:online_variables]
    data[VMS::PACKET_KEYS[:party]]            = party
    data[VMS::PACKET_KEYS[:name]]             = $player.name
    data[VMS::PACKET_KEYS[:trainer_type]]     = $player.trainer_type
    data[VMS::PACKET_KEYS[:map_id]]           = $game_map.map_id
    data[VMS::PACKET_KEYS[:x]]                = $game_player.x
    data[VMS::PACKET_KEYS[:y]]                = $game_player.y
    data[VMS::PACKET_KEYS[:real_x]]           = $game_player.real_x
    data[VMS::PACKET_KEYS[:real_y]]           = $game_player.real_y
    data[VMS::PACKET_KEYS[:direction]]        = $game_player.direction
    data[VMS::PACKET_KEYS[:pattern]]          = $game_player.pattern
    data[VMS::PACKET_KEYS[:graphic]]          = $game_player.character_name
    data[VMS::PACKET_KEYS[:offset_x]]         = $game_player.x_offset
    data[VMS::PACKET_KEYS[:offset_y]]         = $game_player.y_offset
    data[VMS::PACKET_KEYS[:opacity]]          = $game_player.opacity
    data[VMS::PACKET_KEYS[:stop_animation]]   = $game_player.step_anime
    data[VMS::PACKET_KEYS[:animation]]        = $scene.spriteset.getAnimationSprites if $scene.is_a?(Scene_Map) && $scene.spriteset
    data[VMS::PACKET_KEYS[:jump_offset]]      = $game_player.screen_y_ground - $game_player.screen_y - $game_player.y_offset
    data[VMS::PACKET_KEYS[:jumping_on_spot]]  = $game_player.jumping_on_spot
    data[VMS::PACKET_KEYS[:surfing]]          = $PokemonGlobal.surfing
    data[VMS::PACKET_KEYS[:diving]]           = $PokemonGlobal.diving
    data[VMS::PACKET_KEYS[:surf_base_coords]] = $game_temp.surf_base_coords || [nil, nil]
    data[VMS::PACKET_KEYS[:state]]            = $game_temp.vms[:state]
    data[VMS::PACKET_KEYS[:busy]]             = !VMS.interaction_possible?

    data[VMS::PACKET_KEYS[:follower_active]]    = !follower_event.nil?
    data[VMS::PACKET_KEYS[:follower_graphic]]   = follower_event ? follower_event.character_name : ""
    data[VMS::PACKET_KEYS[:follower_direction]] = follower_event ? follower_event.direction : 2

    return data
  end
end