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

  def experience_badge(exp)
    shared_classes = "text-xs font-semibold text-center py-0.5 px-1 rounded"
    content_tag(:span, exp.name, class: "#{shared_classes} bg-green-100 text-green-800")
  end

  def will_paginate(coll_or_options = nil, options = {})
    if coll_or_options.is_a? Hash
      options = coll_or_options
      coll_or_options = nil
    end
    options = options.merge renderer: Pagination::TailwindUIPaginationRenderer unless options[:renderer]
    super(*[coll_or_options, options].compact)
  end

  def format_date(date)
    date.present? ? date.strftime("%d/%m/%Y") : ''
  end

  def item_badge(item_type, label)
    shared_classes = "text-xs font-semibold text-center px-1 py-0.5 rounded"
    content_tag(:span, label, class: "#{shared_classes} #{item_color(item_type)}")
  end

  def lodging_color
    "bg-yellow-200"
  end

  def room_color
    "bg-orange-400"
  end

  def bed_color
    "bg-purple-400"
  end

  def experience_color
    "bg-green-400"
  end

  def space_color
    "bg-blue-400"
  end

  def rental_item_color
    "bg-pink-200"
  end

  def product_color
    "bg-red-400"
  end

  private

  def item_color(item_type)
    case item_type
    when StayItem::EXPERIENCE
      experience_color
    when StayItem::LODGING
      lodging_color
    when StayItem::PRODUCT
      product_color
    when StayItem::RENTAL_ITEM
      rental_item_color
    when StayItem::SPACE
      space_color
    when StayItem::ROOM
      room_color
    when StayItem::BED
      bed_color
    end
  end

end
