# Le Guide des 4 Sources : les visages de ceux qui l'écrivent.
module GuideHelper
  AVATAR_SIZES = {
    sm: "h-6 w-6 text-[0.6rem]",
    md: "h-9 w-9 text-xs",
    lg: "h-11 w-11 text-sm"
  }.freeze

  # La photo du membre lié au compte, sinon ses initiales dans une pastille —
  # même règle que les fils de commentaires.
  def guide_avatar(user, size: :md, extra: nil)
    name = user&.display_name.presence || "Quelqu'un"
    classes = [AVATAR_SIZES.fetch(size), "shrink-0 rounded-full", extra].compact.join(" ")
    human = user&.linked_human

    if human&.photo?
      image_tag human.photo_url(:thumb), class: "#{classes} object-cover", alt: name, title: name
    else
      initials = name.split(/[\s@.]/).compact_blank.first(2).map { |word| word[0] }.join.upcase
      tag.span initials, class: "#{classes} inline-flex items-center justify-center bg-emerald-100 font-semibold text-emerald-800",
                         title: name, aria: { label: name }
    end
  end

  # « 19 octobre 2026 à 14:32 »
  def guide_date(time)
    l(time, format: "%-d %B %Y à %H:%M")
  end
end
