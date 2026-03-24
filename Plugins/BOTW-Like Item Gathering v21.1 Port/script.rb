#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#   Developer-Configurable Constant Defaults
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

FAST_PICK_ITEM_ACTIVE  = 1   # 1 = Items picked up get the BOTW anim.       0 = Old anim.
FAST_PICK_BERRY_ACTIVE = 1   # 1 = Berries harvested get the BOTW anim.     0 = Old anim.
FAST_ITEM_GET_SE       = "Voltorb Flip point"   # Sound that will play after obtaining an item.

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#   Menu Handlers
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

MenuHandlers.add(:options_menu, :botw_item_pickup, {
  "name"        => _INTL("Item Pickup"),
  "order"       => 88,
  "type"        => EnumOption,
  "parameters"  => [_INTL("Default"), _INTL("Instant")],
  "description" => _INTL("Choose whether a message should appear when picking up items."),
  "get_proc"    => proc { next FAST_PICK_ITEM_ACTIVE },
  "set_proc"    => proc { |value, _scene| FAST_PICK_ITEM_ACTIVE = value }
})

MenuHandlers.add(:options_menu, :botw_berry_harvest, {
  "name"        => _INTL("Berry Harvest"),
  "order"       => 89,
  "type"        => EnumOption,
  "parameters"  => [_INTL("Default"), _INTL("Instant")],
  "description" => _INTL("Choose whether a message should appear when harvesting berries."),
  "get_proc"    => proc { next FAST_PICK_BERRY_ACTIVE },
  "set_proc"    => proc { |value, _scene| FAST_PICK_BERRY_ACTIVE = value }
})

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#   UI
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class UISprite < Sprite
  attr_accessor :scroll
  attr_accessor :timer

  def initialize(x, y, bitmap, viewport)
    super(viewport)
    self.bitmap = bitmap
    self.x = x
    self.y = y
    self.z = 999999
    self.zoom_x = 0.5
    self.zoom_y = 0.5
    @scroll = false
    @timer = 0
  end

  def scaled_width
    return self.bitmap.width * self.zoom_x
  end

  def scaled_height
    return self.bitmap.height * self.zoom_y
  end

  def update
    return if disposed?
    @timer += 1
    case @timer
    when 0..10
      self.x += scaled_width / 10.0
    when 100..110
      self.x -= scaled_width / 10.0
    when 111
      dispose
    end
  end
end

class Spriteset_Map
  class UIHandler
    def initialize
      @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      @viewport.z = 999999
      @sprites = []
    end

    def addSprite(x, y, bitmap)
      @sprites.each { |sprite| sprite.scroll = true }
      index = @sprites.length
      @sprites[index] = UISprite.new(x, y, bitmap, @viewport)
    end

    def update
      removed = []
      @sprites.each_index do |key|
        sprite = @sprites[key]
        next if !sprite || sprite.disposed?

        if sprite.scroll
          sprite2 = @sprites[key + 1]
          if sprite2 && !sprite2.disposed?
            if sprite.x >= sprite2.x && sprite.x <= sprite2.x + sprite2.scaled_width
              if sprite.y >= sprite2.y && sprite.y <= sprite2.y + sprite2.scaled_height + 5
                sprite.y += 5
              else
                sprite.scroll = false
              end
            else
              sprite.scroll = false
            end
          else
            sprite.scroll = false
          end
        end

        sprite.update
        removed.push(sprite) if sprite.disposed?
      end

      removed.each { |sprite| @sprites.delete(sprite) }
    end

    def dispose
      @sprites.each do |sprite|
        sprite.dispose if sprite && !sprite.disposed?
      end
      @viewport.dispose if @viewport && !@viewport.disposed?
    end
  end

  alias botw_item_gathering_dispose_old dispose
  alias botw_item_gathering_update_old update

  def dispose
    @ui.dispose if @ui
    botw_item_gathering_dispose_old
  end

  def update
    @ui = UIHandler.new if !@ui
    @ui.update
    botw_item_gathering_update_old
  end

  def ui
    return @ui
  end
end

class Scene_Map
  def addSprite(x, y, bitmap)
    self.spriteset.ui.addSprite(x, y, bitmap)
  end
end

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#   Animation
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def itemAnim(item, qty)
  bitmap = Bitmap.new("Graphics/Pictures/Object")
  pbSetSystemFont(bitmap)
  base = Color.new(248, 248, 248)
  shadow = Color.new(72, 80, 88)
  itemData = GameData::Item.get(item)
  move = GameData::Move.get(itemData.move) if itemData.is_machine?

  if itemData.is_machine?
    itemname = "#{itemData.portion_name} #{move.name}"
    if qty > 1
      textpos = [[_INTL("{1} x{2}", itemname, qty), 5, 15, false, base, shadow]]
    else
      textpos = [[_INTL("{1}", itemname), 5, 15, false, base, shadow]]
    end
  else
    if qty > 1
      textpos = [[_INTL("{1} x{2}", itemData.portion_name_plural, qty), 5, 15, false, base, shadow]]
    else
      textpos = [[_INTL("{1}", itemData.portion_name), 5, 15, false, base, shadow]]
    end
  end

  pbDrawTextPositions(bitmap, textpos)

  if itemData.is_machine?
    if pbResolveBitmap("Graphics/Items/machine_#{move.type}")
      bitmap.blt(274, 5, Bitmap.new("Graphics/Items/machine_#{move.type}"), Rect.new(0, 0, 48, 48))
    end
  else
    if pbResolveBitmap("Graphics/Items/#{itemData.id}")
      bitmap.blt(274, 5, Bitmap.new("Graphics/Items/#{itemData.id}"), Rect.new(0, 0, 48, 48))
    end
  end

  pbSEPlay(FAST_ITEM_GET_SE)
  $scene.addSprite(-(bitmap.width * 0.5), 200, bitmap)
end

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#   Method Overrides
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

alias botw_item_gathering_oldItem pbItemBall
def pbItemBall(item, quantity = 1)
  if FAST_PICK_ITEM_ACTIVE == 0
    botw_item_gathering_oldItem(item, quantity)
  else
    item = GameData::Item.get(item)
    return false if !item || quantity < 1

    itemname = (quantity > 1) ? item.portion_name_plural : item.portion_name
    pocket = item.pocket
    move = item.move
    if item.is_machine?
      itemname += " #{GameData::Move.get(move).name}"
    end

    if $bag.add(item, quantity)
      itemAnim(item, quantity)
      return true
    else
      if item.is_machine?
        if quantity > 1
          pbMessage(_INTL("You found {1} \\c[1]{2} {3}\\c[0]!", quantity, itemname, GameData::Move.get(move).name))
        else
          pbMessage(_INTL("You found \\c[1]{1} {2}\\c[0]!", itemname, GameData::Move.get(move).name))
        end
      elsif quantity > 1
        pbMessage(_INTL("You found {1} \\c[1]{2}\\c[0]!", quantity, itemname))
      elsif itemname.starts_with_vowel?
        pbMessage(_INTL("You found an \\c[1]{1}\\c[0]!", itemname))
      else
        pbMessage(_INTL("You found a \\c[1]{1}\\c[0]!", itemname))
      end
      pbMessage(_INTL("But your Bag is full..."))
      return false
    end
  end
end

alias botw_item_gathering_oldBerry pbPickBerry
def pbPickBerry(berry, qty = 1)
  if FAST_PICK_BERRY_ACTIVE == 0
    botw_item_gathering_oldBerry(berry, qty)
  else
    interp = pbMapInterpreter
    thisEvent = interp.get_self
    berryData = interp.getVariable
    berry = GameData::Item.get(berry)
    itemname = (qty > 1) ? berry.portion_name_plural : berry.portion_name

    if !$bag.can_add?(berry, qty)
      pbMessage(_INTL("Too bad...\nThe Bag is full..."))
      return false
    end

    $stats.berry_plants_picked += 1
    if qty >= GameData::BerryPlant.get(berry.id).maximum_yield
      $stats.max_yield_berry_plants += 1
    end

    $bag.add(berry, qty)
    itemAnim(berry, qty)
    pbSetSelfSwitch(thisEvent.id, "A", true)
    return true
  end
end