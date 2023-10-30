class ExperienceDecorator < ApplicationDecorator
  delegate_all

  def fixed_price
    h.humanized_money_with_symbol(object.fixed_price)
  end

  def participants
    if object.min_participants && object.max_participants
      "De #{object.min_participants} à #{object.max_participants} participants"
    elsif object.min_participants
      "À partir de #{h.pluralize(object.min_participants, "participant", plural: "participants")}"
    else
      "Jusqu'à #{h.pluralize(object.max_participants, "participant", plural: "participants")}"
    end
  end

  def price
    h.humanized_money_with_symbol(object.price)
  end
end
