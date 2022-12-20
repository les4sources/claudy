module CalendarHelper
  def button_to_next_month(current_date)
    link_to(params.permit(:date).merge(date: current_date.next_month), class: "btn-page-header-with-icon") do
      button_label_with_icon(l(current_date.next_month, format: "%B %Y"), "arrow_small_right", right: true)
    end.html_safe
  end

  def button_to_previous_month(current_date)
    link_to(params.permit(:date).merge(date: current_date.prev_month), class: "btn-page-header-with-icon") do
      button_label_with_icon(l(current_date.prev_month, format: "%B %Y"), "arrow_small_left")
    end.html_safe
  end

  # calls the calendar service to build the actual calender
  # def calendar(date = Date.today, from = "public", &block)
  #   Calendar.new(self, date, from, block).table
  # end
end
