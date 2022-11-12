class SimpleCalendar::PublicLodgingsCalendar < SimpleCalendar::Calendar
  private

  def date_range
    beginning = Date.today.beginning_of_week(start_day)
    ending = (Date.today + 1.month).end_of_month.end_of_week(start_day)
    (beginning..ending).to_a
  end

  def end_date
    options.fetch(:end_date)
  end

  def start_day
    :monday
  end
end
