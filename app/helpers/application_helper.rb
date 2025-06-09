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
    when -1
      content_tag(:span, room.code, class: "#{shared_classes} bg-slate-100 text-slate-800")
    when 0
      content_tag(:span, room.code, class: "#{shared_classes} bg-purple-100 text-purple-800")
    when 1
      content_tag(:span, room.code, class: "#{shared_classes} bg-purple-200 text-purple-800")
    when 2
      content_tag(:span, room.code, class: "#{shared_classes} bg-purple-300 text-purple-800")
    end
  end

  def space_badge(space)
    shared_classes = "text-xs font-semibold text-center py-0.5 px-1 rounded"
    content_tag(:span, space.code, class: "#{shared_classes} bg-orange-100 text-orange-800")
  end

  def will_paginate(coll_or_options = nil, options = {})
    if coll_or_options.is_a? Hash
      options = coll_or_options
      coll_or_options = nil
    end
    options = options.merge renderer: Pagination::TailwindUIPaginationRenderer unless options[:renderer]
    super(*[coll_or_options, options].compact)
  end
end
