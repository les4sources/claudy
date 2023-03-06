class RoomDecorator < ApplicationDecorator
  delegate_all

  def checkbox_label
    case level
    when 0
      h.raw("<div>#{name} (rez-de-chaussée)</div><div class='mt-1 text-slate-500'>#{description}</div>")
    when 1
      h.raw("<div>#{name} (1er étage)</div><div class='mt-1 text-slate-500'>#{description}</div>")
    when 2
      h.raw("<div>#{name} (2ème étage)</div><div class='mt-1 text-slate-500'>#{description}</div>")
    end
  end

  def level_name
    case level
    when 0
      "Rez-de-chaussée"
    when 1
      "1er étage"
    when 2
      "2ème étage"
    end
  end
end
