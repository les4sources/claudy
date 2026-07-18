module CalendarHelper
  # --- Couleur déterministe par séjour (epic #66, Phase 4) -----------------
  # Le calendrier regroupe et colore les occupations PAR SÉJOUR (`stay_id`).
  # La teinte dérive de l'id du séjour via l'angle d'or (137,508°) qui répartit
  # les teintes le plus loin possible les unes des autres — deux séjours voisins
  # obtiennent donc des couleurs bien distinctes.
  #
  # Le rendu passe par du STYLE INLINE et NON par des classes Tailwind : une
  # classe dynamique (`bg-[hsl(...)]` / `bg-#{...}`) est invisible au scan JIT de
  # Tailwind et ne serait jamais générée. Le style inline est garanti au runtime.
  GOLDEN_ANGLE = 137.508

  # Teinte HSL (0–359) stable pour un séjour donné.
  def stay_hue(stay_id)
    ((stay_id.to_i * GOLDEN_ANGLE) % 360).round
  end

  # Style d'accent d'un bloc calendrier groupé par séjour : bordure gauche
  # colorée + fond très clair de la même teinte. Combiné avec `border-l-4`.
  def stay_block_style(stay_id)
    hue = stay_hue(stay_id)
    "border-left-color: hsl(#{hue}, 65%, 45%); background-color: hsl(#{hue}, 70%, 96%);"
  end

  def button_to_next_month(current_date, data = {}, options = {})
    link_to(params.permit(:date, :no_title, :view).merge(date: current_date.next_month), class: "btn-page-header-with-icon", data: data) do
      if options[:no_label].nil?
        button_label_with_icon(l(current_date.next_month, format: "%B %Y"), "arrow_small_right", right: true)
      else
        button_label_with_icon(nil, "arrow_small_right", right: true)
      end
    end.html_safe
  end

  def buttons_to_next_months(current_date, data = {})
    content_tag(:div, class: "inline-flex flex-wrap rounded-md shadow-sm", role: "group") do
      links = []
      links << link_to(params.permit(:date, :view).merge(date: current_date.next_month), class: "btn-group-page-header-with-icon border rounded-l-lg bg-blue-100", data: data) do
        l(current_date.next_month, format: "%B %Y")
      end
      links << link_to(params.permit(:date, :view).merge(date: current_date + 2.months), class: "hidden md:inline-flex btn-group-page-header-with-icon bg-blue-200", data: data) do
        l(current_date + 2.months, format: "%B %Y")
      end
      links << link_to(params.permit(:date, :view).merge(date: current_date + 3.months), class: "hidden md:inline-flex btn-group-page-header-with-icon border rounded-r-md bg-blue-300", data: data) do
        button_label_with_icon(l(current_date + 3.months, format: "%B %Y"), "arrow_small_right", right: true)
      end
      links.join.html_safe
    end
  end

  def button_to_previous_month(current_date, data = {}, options = {})
    link_to(params.permit(:date, :no_title, :view).merge(date: current_date.prev_month), class: "btn-page-header-with-icon", data: data) do
      if options[:no_label].nil?
        button_label_with_icon(l(current_date.prev_month, format: "%B %Y"), "arrow_small_left")
      else
        button_label_with_icon(nil, "arrow_small_left")
      end
    end.html_safe
  end

  def buttons_to_previous_months(current_date, data = {})
    content_tag(:div, class: "inline-flex flex-wrap rounded-md shadow-sm mr-2", role: "group") do
      links = []
      links << link_to(params.permit(:date, :view).merge(date: current_date - 3.months), class: "hidden md:inline-flex btn-group-page-header-with-icon border rounded-l-lg bg-blue-300", data: data) do
        button_label_with_icon(l(current_date - 3.months, format: "%B %Y"), "arrow_small_left")
      end
      links << link_to(params.permit(:date, :view).merge(date: current_date - 2.months), class: "hidden md:inline-flex btn-group-page-header-with-icon bg-blue-200", data: data) do
        l(current_date - 2.months, format: "%B %Y")
      end
      links << link_to(params.permit(:date, :view).merge(date: current_date.prev_month), class: "btn-group-page-header-with-icon border rounded-r-md bg-blue-100", data: data) do
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
