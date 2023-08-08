module CalendarHelper
  def button_to_next_month(current_date, data = {})
    link_to(params.permit(:date).merge(date: current_date.next_month), class: "btn-page-header-with-icon", data: data) do
      button_label_with_icon(l(current_date.next_month, format: "%B %Y"), "arrow_small_right", right: true)
    end.html_safe
  end

  def buttons_to_next_months(current_date, data = {})
    content_tag(:div, class: "hidden md:inline-flex rounded-md shadow-sm", role: "group") do
      links = []
      links << link_to(params.permit(:date).merge(date: current_date.next_month), class: "btn-group-page-header-with-icon border rounded-l-lg bg-blue-100", data: data) do
        l(current_date.next_month, format: "%B %Y")
      end
      links << link_to(params.permit(:date).merge(date: current_date + 2.months), class: "btn-group-page-header-with-icon bg-blue-200", data: data) do
        l(current_date + 2.months, format: "%B %Y")
      end
      links << link_to(params.permit(:date).merge(date: current_date + 3.months), class: "btn-group-page-header-with-icon border rounded-r-md bg-blue-300", data: data) do
        button_label_with_icon(l(current_date + 3.months, format: "%B %Y"), "arrow_small_right", right: true)
      end
      links.join.html_safe
    end
  end

  def button_to_previous_month(current_date, data = {})
    link_to(params.permit(:date).merge(date: current_date.prev_month), class: "btn-page-header-with-icon", data: data) do
      button_label_with_icon(l(current_date.prev_month, format: "%B %Y"), "arrow_small_left")
    end.html_safe
  end

  def buttons_to_previous_months(current_date, data = {})
    content_tag(:div, class: "hidden md:inline-flex rounded-md shadow-sm mr-2", role: "group") do
      links = []
      links << link_to(params.permit(:date).merge(date: current_date - 3.months), class: "btn-group-page-header-with-icon border rounded-l-lg bg-blue-300", data: data) do
        button_label_with_icon(l(current_date - 3.months, format: "%B %Y"), "arrow_small_left")
      end
      links << link_to(params.permit(:date).merge(date: current_date - 2.months), class: "btn-group-page-header-with-icon bg-blue-200", data: data) do
        l(current_date - 2.months, format: "%B %Y")
      end
      links << link_to(params.permit(:date).merge(date: current_date.prev_month), class: "btn-group-page-header-with-icon border rounded-r-md bg-blue-100", data: data) do
        l(current_date.prev_month, format: "%B %Y")
      end
      links.join.html_safe
    end
  end

  # calls the calendar service to build the actual calender
  # def calendar(date = Date.today, from = "public", &block)
  #   Calendar.new(self, date, from, block).table
  # end
end
