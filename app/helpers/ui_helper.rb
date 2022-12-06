# coding: utf-8
module UiHelper
  def button_label_with_count(label, count, options = {})
    out = ActiveSupport::SafeBuffer.new
    out << label
    out << content_tag(:span, count, class: "count #{"count--zero" if count == 0} #{"count--tab" if options[:tab]}")
  end

  def button_label_with_icon(label, icon, options = {})
    out = ActiveSupport::SafeBuffer.new
    if options[:right]
      out << label
      out << content_tag(:span, render("layouts/icons/#{icon}"), class: "inline-icon inline-icon--right #{options[:icon_class]}")
    else
      out << content_tag(:span, render("layouts/icons/#{icon}"), class: "inline-icon #{options[:icon_class]}")
      out << label
    end
    out
  end

  def callout(type, content:, tiny: false, dashed: false, link_label: nil, link_href: nil, link_options: {})
    out = ActiveSupport::SafeBuffer.new
    if link_label && link_href
      out << content_tag(:div, class: "cell small-12 medium-shrink") do
        if tiny
          link_to(link_label, link_href, link_options.merge({ class: "tiny hollow #{type} button small-only-expanded no-margin-bottom" }))
        else
          link_to(link_label, link_href, link_options.merge({ class: "small hollow #{type} button small-only-expanded no-margin-bottom" }))
        end
      end
    end
    out = content_tag(:div, class: "#{type} callout #{tiny ? "callout--tiny" : nil} #{dashed ? "callout--dashed" : nil}") do
      content_tag(:div, class: "grid-x align-middle") do
        content_tag(:div, class: "cell small-12 medium-auto") do
          content_tag(:strong, content)
        end + out
      end
    end
    out.html_safe
  end

  def close_modal_button
    content_tag(:button, "data-close": "", class: "close-button", "aria-label": "Close modal", type: "button") do
      content_tag(:span, raw("&times;"), "aria-hidden": true)
    end.html_safe
  end

  def ellipsis_for(toggled_item_dom_id)
    content_tag(
      :span,
      ui__icon("navigation_menu_horizontal"),
      class: "inline-icon",
      data: {
        toggle: toggled_item_dom_id
      }
    ).html_safe
  end

  def icons_list_item(icon: nil, label: nil)
    out = ActiveSupport::SafeBuffer.new
    if icon
      out << content_tag(:div, class: "cell shrink") do
        content_tag(:div, render("layouts/icons/#{icon}"), class: "icons-list__item__icon")
      end
    end
    if label
      out << content_tag(:div, class: "cell auto") do
        out2 = ActiveSupport::SafeBuffer.new
        out2 << content_tag(:div, nil, class: "spacer__width--dot5")
        out2 << label
        content_tag(:div, out2, class: "icons-list__item__label")
      end
    end
    content_tag(:div, class: "icons-list__item") do
      content_tag(:div, out, class: "grid-x align-middle")
    end
  end

  def info_header(label, **opts)
    content_tag(:div, class: "info__header grid-x grid-padding-x") do
      content_tag(:div, class: "cell small-12") do
        content_tag(:h4, label, **opts)
      end
    end
  end

  def info_line(label, **opts, &block)
    title_class = if opts[:title_class].present?
                    opts[:title_class]
                  else
                    ''
                  end
    value_class = if opts[:value_class].present?
                    opts[:value_class]
                  else
                    ''
                  end
    out = ActiveSupport::SafeBuffer.new
    out << content_tag(:div, class: "info__line grid-x grid-padding-x") do
      out_cells = ActiveSupport::SafeBuffer.new
      out_cells << content_tag(:div, class: "cell small-12") do
        content_tag(:strong, label, class: "info__line__label #{title_class}")
      end
      out_cells << content_tag(:div, class: "cell small-12 #{value_class}") do
        yield block
      end
      out_cells
    end
    out << content_tag(:div, nil, class: "spacer-1")
    out
  end

  def legend_item(color: nil, label: nil)
    content_tag(:div, class: "legend__item") do
      content_tag(:div, class: "grid-x align-middle") do
        out = ActiveSupport::SafeBuffer.new
        out << content_tag(:div, class: "cell shrink") do
          content_tag(:div, nil, class: "legend__item__color", style: "background-color: #{color}")
        end
        out << content_tag(:div, class: "cell auto") do
          content_tag(:div, label, class: "legend__item__label")
        end
        out
      end
    end
  end

  def section_heading_tw(heading:, extra: nil, spacing: :hr, count: nil, icon: nil, span_id:nil)
    out = ActiveSupport::SafeBuffer.new
    out << content_tag(:div, class: "mb-4 pb-4 border-b border-gray-200") do
      out2 = ActiveSupport::SafeBuffer.new
      out2 << content_tag(:h3, heading, class: "text-lg font-medium leading-6 text-gray-900")
      if extra
        out2 << content_tag(p, extra, class: "mt-1 text-sm text-gray-500")
      end
      out2
    end
    out.html_safe
  end

  def section_heading(heading:, extra: nil, spacing: :hr, count: nil, icon: nil, span_id:nil)
    out = ActiveSupport::SafeBuffer.new
    if spacing == :hr
      out << content_tag(:div, class: "grid-x") do
        content_tag(:div, class: "cell auto") do
          content_tag(:hr)
        end
      end
    elsif spacing == :spacer
      out << content_tag(:div, nil, class: "spacer-2 spacer--2 spacer--heading")
    end
    out << content_tag(:div, class: "grid-x section-heading align-middle") do
      heading_cell_classes = "cell small-12 medium-auto"
      extra_cell_classes = "cell small-12 medium-shrink cell--extra"
      # # move forms below heading on medium screens
      # if extra&.include?("<form")
      #   heading_cell_classes = "cell small-12 medium-12 large-auto"
      #   extra_cell_classes = "cell small-12 medium-12 large-shrink"
      # end
      out2 = ActiveSupport::SafeBuffer.new
      out2 << content_tag(:div, class: heading_cell_classes) do
        content_tag(:h3, class: "no-margin-bottom #{icon ? 'with-icon' : 'without-icon'}") do
          out3 = ActiveSupport::SafeBuffer.new
          out3 << render("layouts/icons/#{icon}") if icon
          out3 << content_tag(:span, heading, id: span_id)
          out3 << content_tag(:span, count, class: "count") if count
          out3
        end
      end
      out2 << content_tag(:div, class: extra_cell_classes) do
        out3 = ActiveSupport::SafeBuffer.new
        out3 << content_tag(:div, nil, class: "spacer-05 spacer--05 hide-for-medium")
        if extra.kind_of?(Array)
          extra.reject(&:nil?).each { |e| out3 << e + " " }
        else
          out3 << extra
        end
        out3
      end
      out2
    end
    out << content_tag(:div, nil, class: "spacer-1 spacer--1")
    out.html_safe
  end

  def text_with_icon(icon, label, options = {})
    icon_classes = Array.wrap(options[:icon_class])
    icon_classes.map! { |icon_class| "inline-icon--#{icon_class}" }
    content_tag(:div) do
      content_tag(
        :span,
        render_icon("layouts/icons/#{icon}"),
        class: icon_classes&.unshift("inline-icon") || "inline-icon"
      ) + " " + raw(label)
    end
  end

  def ui__icon(filename)
    render("layouts/icons/#{filename}")
  end

  def ui__label(content: nil, label_class: nil, title: nil)
    if title.nil?
      content_tag(:span, content, class: "#{label_class} label")
    else
      content_tag(:span, content, class: "#{label_class} label", title: title, data: { tooltip: true })
    end
  end
end
