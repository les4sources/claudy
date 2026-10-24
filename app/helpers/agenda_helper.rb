# Agenda en rubans (nouvelle interface, Michael 2026-10-24).
module AgendaHelper
  # Où mène une bande : le séjour (dans sa modale), sinon la fiche de ce
  # qu'elle montre quand le rôle la lit. nil = une bande qu'on lit sans ouvrir.
  def agenda_ribbon_path(ribbon)
    record = ribbon.record
    if ribbon.stay
      stay_path(ribbon.stay) if section_readable?(:full)
    elsif record.is_a?(Booking)
      booking_path(record) if section_readable?(:full)
    elsif record.is_a?(SpaceBooking)
      space_booking_path(record) if section_readable?(:full)
    elsif record.is_a?(Event)
      event_path(record) if section_readable?(:events)
    elsif record.is_a?(MealOrder)
      edit_kitchen_order_path(record) if section_writable?(:full)
    end
  end

  # « du 24 au 27 octobre », « le 24 octobre » : la fin de l'intitulé lu d'une
  # bande de séjour.
  def agenda_stay_dates(stay)
    from = stay&.arrival_date
    to = stay&.departure_date
    return nil if from.nil? || to.nil?
    return "le #{l(from, format: '%-d %B')}" if from == to

    "du #{l(from, format: '%-d %B')} au #{l(to, format: '%-d %B')}"
  end

  # Le nom d'une journée dans la liste du téléphone : « Aujourd'hui · samedi
  # 24 », « Demain · dimanche 25 », sinon « lundi 26 ».
  def agenda_day_heading(date)
    name = l(date, format: "%A %-d")
    case (date - Date.current).to_i
    when 0 then "Aujourd’hui · #{name}"
    when 1 then "Demain · #{name}"
    when -1 then "Hier · #{name}"
    else name
    end
  end
end
