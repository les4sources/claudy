class GatheringDecorator < ApplicationDecorator
  delegate_all
  decorates_association :gathering_category

  def display_name
    object.name.presence || default_name
  end

  def default_name
    "#{object.gathering_category.name} du #{h.l(object.starts_at.to_date)}"
  end

  def color
    object.gathering_category.color
  end

  def calendar_class
    [
      "shadow-sm",
      "border-l-4",
      "border-l-#{color}-500",
      "bg-#{color}-50"
    ].join(" ")
  end

  def color_dot
    h.content_tag(:span, "", class: "inline-block shrink-0 mr-1.5 w-2.5 h-2.5 rounded-full bg-#{color}-400")
  end

  def name_with_color
    h.safe_join([color_dot, h.content_tag(:span, display_name, class: "truncate")])
  end

  def date_range
    if single_day?
      "#{h.l(object.starts_at.to_date, format: :long)} · #{time_only(object.starts_at)}–#{time_only(object.ends_at)}"
    else
      "Du #{h.l(object.starts_at.to_date)} au #{h.l(object.ends_at.to_date)}"
    end
  end

  def time_range_for_day(date)
    if single_day?
      "#{time_only(object.starts_at)}–#{time_only(object.ends_at)}"
    elsif date == object.starts_at.to_date
      "dès #{time_only(object.starts_at)}"
    elsif date == object.ends_at.to_date
      "jusque #{time_only(object.ends_at)}"
    else
      "toute la journée"
    end
  end

  def single_day?
    object.starts_at.to_date == object.ends_at.to_date
  end

  def time_only(datetime)
    datetime.strftime("%H:%M").sub(":00", "h").sub(":", "h")
  end

  def full_day?
    single_day? && object.starts_at.seconds_since_midnight == 0 &&
      (object.ends_at - object.starts_at) >= 23.hours
  end

  def notes_preview(limit: 120)
    return nil unless object.notes.present?
    h.truncate(object.notes.to_plain_text, length: limit, separator: " ")
  end
end
