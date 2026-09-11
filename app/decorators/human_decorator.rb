class HumanDecorator < ApplicationDecorator
  delegate_all

  # Les pôles en badges compacts (epic #239, phase 4). L'index de l'équipe est
  # un tableau : une liste à puces y ferait exploser la hauteur de ligne, alors
  # qu'un badge par pôle se lit d'un coup d'œil. Le référent·e se distingue —
  # c'est la seule information de rôle qui change quelque chose au quotidien.
  def team_badges
    memberships = object.team_memberships.includes(:team).select { |m| m.team.present? }
    return h.content_tag(:span, "—", class: "text-gray-300") if memberships.empty?

    h.safe_join(
      memberships.sort_by { |m| m.team.name }.map { |membership| team_badge(membership) },
      " ".html_safe
    )
  end

  def status_badge
    case object.status
    when "active"
      h.content_tag(:span, "actif", class: "inline-flex items-center rounded-md bg-green-50 px-1.5 py-0.5 text-xs font-medium text-green-700 ring-1 ring-inset ring-green-600/20")
    when "inactive"
      h.content_tag(:span, "inactif", class: "inline-flex items-center rounded-md bg-red-50 px-1.5 py-0.5 text-xs font-medium text-red-700 ring-1 ring-inset ring-red-600/20")
    end
  end

  private

  def team_badge(membership)
    referent = membership.role == "referent"
    classes = if referent
                "inline-flex items-center gap-1 rounded-full bg-teal-100 px-2 py-0.5 text-xs font-medium text-teal-800"
              else
                "inline-flex items-center rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-700"
              end

    h.link_to(h.team_path(membership.team), class: classes, title: membership.role_label) do
      h.safe_join([
        (h.content_tag(:span, "★", class: "text-teal-600", "aria-hidden": true) if referent),
        membership.team.name
      ].compact)
    end
  end
end
