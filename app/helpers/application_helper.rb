module ApplicationHelper
  ActionView::Base.default_form_builder = FormBuilders::TailwindFormBuilder

  def delete_link(resource, text_label = "Supprimer")
    link_to text_label,
            send("#{resource.class.name.underscore}_path", resource),
            data: { turbo_method: :delete, turbo_confirm: "Merci de plutôt passer le statut à 'annulé' pour une annulation de réservation. Etes-vous sûr•e de vouloir supprimer?" },
            class: "btn-destroy"
  end

  def room_badge(room)
    shared_classes = "text-xs font-semibold text-center px-1 py-0.5 rounded"
    case room.level
    when 0
      content_tag(:span, room.code, class: "#{shared_classes} bg-indigo-100 text-indigo-800")
    when 1
      content_tag(:span, room.code, class: "#{shared_classes} bg-purple-100 text-purple-800")
    when 2
      content_tag(:span, room.code, class: "#{shared_classes} bg-pink-100 text-pink-800")
    end
  end

  def space_badge(space)
    shared_classes = "text-xs font-semibold text-center py-0.5 px-1 rounded"
    content_tag(:span, space.code, class: "#{shared_classes} bg-indigo-100 text-indigo-800")
  end
end
