def pbInteractOverworldEncounter
  return if $PokemonGlobal.bridge > 0
  $game_temp.overworld_encounter = true
  evt = pbMapInterpreter.get_self
  evt.lock
  pkmn = evt.variable[0]
  return pbDestroyOverworldEncounter(evt) if pkmn.nil?

  GameData::Species.play_cry_from_pokemon(pkmn)
  name = pkmn.name
  name_half = (name.length.to_f / 2).ceil
  textcol = VOESettings::COLORFUL_TEXT ? ((pkmn.genderless?) ? "" : (pkmn.male?) ? "\\b" : "\\r") : ""
  pbMessage(_INTL("{1}{2}!", textcol, name[0, name_half] + name[name_half] + name[name_half]))

  safari_maps = [155, 157, 159, 161]

  if defined?(pbInSafari?) && pbInSafari? && safari_maps.include?($game_map.map_id)
    decision = pbSafariBattle(pkmn.species, pkmn.level)
  else
    decision = WildBattle.start(pkmn)
  end

  $game_temp.overworld_encounter = false
  pbDestroyOverworldEncounter(evt, decision == 4, decision != 4)
end

def pbTrainersSeePkmn(evt)
  result = false
  # If event is running
  return result if $game_system.map_interpreter.running?
  # All event loops
  $game_map.events.each_value do |event|
    next if !event.name[/trainer\((\d+)\)/i] && !event.name[/sight\((\d+)\)/i]
    distance = $~[1].to_i
    next if !pbEventCanReachPlayer?(event, evt, distance)
    next if event.jumping? || event.over_trigger?
    result = true
  end
  return result
end

def get_grass_tile
  possible_tiles = []
  possible_distance = (VOESettings::MAX_DISTANCE * 0.75).round
  (($game_player.x - possible_distance)..($game_player.x + possible_distance)).each do |x|
    # Don't check if out of bounds
    next if x < 0 || x >= $game_map.width
    (($game_player.y - possible_distance)..($game_player.y + possible_distance)).each do |y|
      # Don't check if out of bounds
      next if y < 0 || y >= $game_map.height
      # Don't check if on top of the player
      next if x == $game_player.x && y == $game_player.y
      # Don't spawn on impassable tiles
      next if !$game_map.passable?(x, y, 0) unless VOESettings::WATER_TILES.include?($game_map.terrain_tag(x, y).id)
      # Don't spawn if on top of an event
      on_top = false
      $game_map.events.each_value do |event|
        next unless event.at_coordinate?(x, y)
        on_top = true
        break
      end

      # Returning by Tile Ids
      next if $game_map.terrain_tag(x, y).id == :Rock
      next if on_top

      #echoln "get_grass_tile: #{$game_map.terrain_tag(x, y).id}"

      # Don't spawn if a trainer can see it
      next if pbTrainersSeePkmn(Temp_Event.new(x, y, $game_map.map_id))
      # Spawn only if on an encounter tile

      #echoln "get_grass_tile id: #{$game_map.terrain_tag(x, y).id} (#{$game_map.terrain_tag(x, y).id.class.to_s})"
      next unless
        VOESettings::GRASS_TILES.include?($game_map.terrain_tag(x, y).id) ||
        VOESettings::WATER_TILES.include?($game_map.terrain_tag(x, y).id) ||
        $PokemonEncounters.has_cave_encounters?

      # Add to possible tiles
      possible_tiles.push([x, y])

      if VOESettings::WATER_SPAWNS_ONLY_SURFING
        possible_tiles.dup.each do |tile|
          possible_tiles.delete(tile) if VOESettings::WATER_TILES.include?($game_map.terrain_tag(tile[0], tile[1]).id) unless $PokemonGlobal.surfing
        end
      end

      if VOESettings::BLACK_LIST_WATER.include?($game_map.map_id)
        possible_tiles.dup.each do |tile|
          possible_tiles.delete(tile) if VOESettings::WATER_TILES.include?($game_map.terrain_tag(tile[0], tile[1]).id)
        end
      end
    end
  end
  return (possible_tiles.empty? ? [] : possible_tiles.sample)
end

def pbDestroyOverworldEncounter(event, animation = true, play_sound = false)
  return if $scene.is_a?(Scene_Intro) || $scene.is_a?(Scene_DebugIntro)
  return if event.variable.nil?
  unless $game_variables[1] == 1 || $game_variables[1] == 4
    return if event.variable[0].shiny? && VOESettings::DELETE_SHINY == false
  end
  echoln "Despawning #{event.variable[0].name}" if VOESettings::LOG_SPAWNS
  if play_sound
    dist = (((event.x - $game_player.x).abs + (event.y - $game_player.y).abs) / 4).floor
    pbSEPlay(VOESettings::FLEE_SOUND, [75, 65, 55, 40, 27, 22, 15][dist], 150) if dist <= 6 && dist >= 0 unless dist.nil?
  end
  spriteset = $scene.spriteset($game_map.map_id)
  spriteset&.addUserAnimation(VOESettings::SPAWN_ANIMATION, event.x, event.y, true, 1) if animation
  if VOESettings::DELETE_EVENTS
    Rf.delete_event(event.variable[1])
  else
    event.setVariable(nil)
    event.moveto(0, 0)
    event.through = true
    event.character_name = ""
  end
  VOESettings.current_encounters -= 1
  $game_variables[1] = 0
end

def pbDistanceToPlayer(evt)
  return if !evt
  dx = evt.x - $game_player.x
  dy = evt.y - $game_player.y
  return Math.sqrt(dx * dx + dy * dy).round
end

def pbPokemonIdle(evt)
  return if rand(3) == 1
  return if !evt
  return if evt.lock?
  return pbDestroyOverworldEncounter(evt) if evt.variable.nil?
  if rand(225) == 1 ||
     (!VOESettings::GRASS_TILES.include?($game_map.terrain_tag(evt.x, evt.y).id)) &&
     (!VOESettings::WATER_TILES.include?($game_map.terrain_tag(evt.x, evt.y).id)) &&
       (!$PokemonEncounters.has_cave_encounters? && !$PokemonGlobal.diving) || ($game_map.terrain_tag(evt.x, evt.y).id != :UnderwaterGrass && $PokemonGlobal.diving)
    unless evt.variable[0].shiny?
      pbDestroyOverworldEncounter(evt)
      return
    end
  end
  evt.move_random
  dist = (((evt.x - $game_player.x).abs + (evt.y - $game_player.y).abs) / 4).floor
  pbDestroyOverworldEncounter(evt) if pbDistanceToPlayer(evt) > VOESettings::MAX_DISTANCE && !evt.variable[0].shiny?
  GameData::Species.play_cry_from_pokemon(evt.variable[0], [75, 65, 55, 40, 27, 22, 15][dist]) if dist <= 6 && dist >= 0 && rand(20) == 1 unless dist.nil?
end

def pbChangeEventSprite(event, pkmn, water = false)
  shiny = pkmn.shiny?
  shiny = pkmn.superVariant if (pkmn.respond_to?(:superVariant) && !pkmn.superVariant.nil? && pkmn.super_shiny?)

  fname = ""
  fname = pbOWSpriteFilename(pkmn.species, pkmn.form, pkmn.gender, shiny, pkmn.shadow, water)
  fname = pbOWSpriteFilename(pkmn.species, 0, pkmn.gender, shiny, pkmn.shadow, water) if pkmn.species == :MINIOR

  raise "Following Pokémon sprites were not found." if nil_or_empty?(fname)
  fname.gsub!("Graphics/Characters/", "")
  event.character_name = fname
  if event.move_route_forcing
    hue = pkmn.respond_to?(:superHue) && pkmn.super_shiny? ? pkmn.superHue : 0
    event.character_hue = hue
  end
end

class Game_Temp
  attr_accessor :overworld_encounter
  attr_accessor :frames_updated

  def overworld_encounter
    @overworld_encounter = false if !@overworld_encounter
    return @overworld_encounter
  end

  def overworld_encounter=(val)
    @overworld_encounter = val
  end

  def frames_updated
    @frames_updated = 0 if !@frames_updated
    return @frames_updated
  end

  def frames_updated=(val)
    @frames_updated = val
  end
end

# Added map_id attr to be compatible with pbEventCanReachPlayer at v21.1 Bug Fixes
class Temp_Event
  attr_reader :x, :y, :map_id

  def initialize(x, y, map_id)
    @x = x
    @y = y
    @map_id = map_id
  end
end
