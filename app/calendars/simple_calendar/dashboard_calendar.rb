class SimpleCalendar::DashboardCalendar < SimpleCalendar::Calendar
  private

  def date_range
    beginning = options[:today].beginning_of_month.beginning_of_week(start_day)
    ending = (options[:today] + 2.months).end_of_month.end_of_week(start_day)
    (beginning..ending).to_a
  end

  def end_date
    options.fetch(:end_date)
  end

  def start_day
    :monday
  end
end
