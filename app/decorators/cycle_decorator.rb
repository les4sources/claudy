class CycleDecorator < ApplicationDecorator
  delegate_all

  def formatted_dates
    "#{h.l(object.start_date, format: :long)} — #{h.l(object.end_date, format: :long)}"
  end

  def duration_in_weeks
    days = (object.end_date - object.start_date).to_i
    weeks = days / 7
    remaining = days % 7
    parts = []
    parts << "#{weeks} sem." if weeks > 0
    parts << "#{remaining} j." if remaining > 0
    parts.join(" ")
  end

  def active?
    Date.today.between?(object.start_date, object.end_date)
  end
end
