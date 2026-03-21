class Passwords
  def self.redeemed?(code)
    $PokemonGlobal.redeemed_passwords ||= {}
    return $PokemonGlobal.redeemed_passwords[code] == true
  end

  def self.redeem(code)
    $PokemonGlobal.redeemed_passwords ||= {}
    $PokemonGlobal.redeemed_passwords[code] = true
  end

  def self.ShinyCharm
    code = "ShinyCharm"
    if redeemed?(code)
      pbMessage(_INTL("You have already redeemed this code."))
      return
    end
    pbMessage(_INTL("You obtained the Shiny Charm!"))
    $bag.add(:SHINYCHARM, 1)
    redeem(code)
  end

  def self.QuickPack
    code = "QuickPack"
    if redeemed?(code)
      pbMessage(_INTL("You have already redeemed this code."))
      return
    end
    pbMessage(_INTL("You received 10 Quick Balls!"))
    $bag.add(:QUICKBALL, 10)
    redeem(code)
  end

def self.StrangeEgg
  code = "StrangeEgg"
  if redeemed?(code)
    pbMessage(_INTL("You have already redeemed this code."))
    return
  end

  pbMessage(_INTL("You received a strange egg!"))

  # Change species to generate new Egg
  pbGenerateEgg(:WYNAUT, "Password Gift")

  # The newly generated egg is the last Pokémon in the party
  egg = $player.party[-1]
  egg.shiny = true
  egg.steps_to_hatch = 50

  redeem(code)
end


  def self.GreatPack
    code = "GreatPack"
    if redeemed?(code)
      pbMessage(_INTL("You have already redeemed this code."))
      return
    end
    pbMessage(_INTL("You received 10 Great Balls!"))
    $bag.add(:GREATBALL, 10)
    redeem(code)
  end

  def self.RarePack
    code = "RarePack"
    if redeemed?(code)
      pbMessage(_INTL("You have already redeemed this code."))
      return
    end
    pbMessage(_INTL("You received 10 Rare Candies!"))
    $bag.add(:RARECANDY, 10)
    redeem(code)
  end

  def self.not
    pbMessage(_INTL("<ac>This is an invalid password, or isn't a password at all.<ac>"))
  end
end

class PasswordEntering
  def self.enterCode
    vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
    vp.z = 99999
    sp = { "base" => AnimatedPlane.new(vp) }
    if pbResolveBitmap("Graphics/UI/Pokegear/bg_password")
      sp["base"].setBitmap("Graphics/UI/Pokegear/bg_password")
    end

    pbFadeInAndShow(sp)

    code = pbMessageFreeText("Enter a passcode.", _INTL(""), false, 20)
    case code
    when "ShinyCharm"
      Passwords.ShinyCharm
    when "QuickPack"
      Passwords.QuickPack
    when "StrangeEgg"
      Passwords.StrangeEgg
    when "GreatPack"
      Passwords.GreatPack
    when "RarePack"
      Passwords.RarePack
    else
      Passwords.not
    end

    pbFadeOutAndHide(sp)
    pbDisposeSpriteHash(sp)
    vp.dispose
  end
end

MenuHandlers.add(:pokegear_menu, :Passcodes, {
  "name"      => _INTL("Passcodes"),
  "icon_name" => "Passcodes",
  "order"     => 50,
  "effect"    => proc { |menu|
    if pbConfirmMessage(_INTL("Would you like to enter a Passcode?"))
      pbFadeOutIn { PasswordEntering.enterCode }
    end
    next false
  }
})