class Components::MenuPresenter < PresenterBase
  attr_reader :active_primary, :active_secondary, :active_tertiary,
    :primary_secondary_items, :object, :controller_name, :action_name,
    :view_context

  def initialize(
    view_context: nil,
    active_primary: nil,
    active_secondary: nil,
    active_tertiary: nil,
    object: nil,
    controller_name: nil,
    action_name: nil
  )
    @view_context         = view_context

    @active_primary       = active_primary
    @active_secondary     = active_secondary
    @active_tertiary      = active_tertiary

    @object               = object
    @controller_name      = controller_name
    @action_name          = action_name

    @primary_left_items   = primary_left_items
    @primary_right_items  = primary_right_items
    @secondary_items      = secondary_items
    @tertiary_items       = tertiary_items
  end

  def render_primary_left_menu(options = {})
    render_menu_items(@primary_left_items, "primary", options)
  end

  def render_primary_right_menu(options = {})
    render_menu_items(@primary_right_items, "primary", options)
  end

  def render_secondary_menu(options = {})
    render_menu_items(@secondary_items, "secondary", options)
  end

  def render_tertiary_menu(options = {})
    render_menu_items(@tertiary_items, "tertiary", options)
  end

  def render_menu_items(menu_items, level, options = {})
    if menu_items.present?
      ul_options = { class: ["menu", options[:class]] }
      if options[:dropdown]
        ul_options[:class] << "dropdown"
        ul_options[:"data-dropdown-menu"] = ""
      end
      content_tag(:ul, ul_options) do
        menu_items
        .each_with_index
        .inject(ActiveSupport::SafeBuffer.new) do |buffer, (item, index)|
          if item.fetch(:condition, true)
            buffer << render_menu_item(item, level, index)
          end
          buffer
        end
      end
    end
  end

  def render_menu_item(menu_item, level, index)
    content_tag(:li, class: menu_item_css(menu_item, index)) do
      buffer = ActiveSupport::SafeBuffer.new
      buffer << render_menu_item_link(menu_item)
      if menu_item[:children]
        buffer << render_menu_items(menu_item[:children], level)
      end
      if menu_item.fetch(:active, false) and level == "primary"
        buffer << render_menu_items(
          @secondary_items,
          "secondary",
          class: "nested vertical"
        )
      end
      buffer
    end
  end

  def render_menu_item_link(menu_item)
    link_to(
      raw(menu_item[:body]),
      menu_item[:url],
      menu_item[:html_options],
    )
  end

  def menu_item_css(menu_item, _index)
    css = []

    css << "active" if menu_item[:active]
    css << "hide-for-small-only" if menu_item[:hide_for_small]
    css << menu_item[:class]

    css.reject(&:blank?).presence
  end

  def primary_left_items
    [
      {
        body: "Claudy",
        url: root_path,
        class: "menu-text show-for-large"
      },
      {
        body: "Réservations",
        url: bookings_path,
        active: @active_primary == "bookings"
      },
      {
        body: "Hébergements",
        url: lodgings_path,
        active: @active_primary == "lodgings"
      }
    ]
  end

  def primary_right_items
    []
  end

  def secondary_items
    case @active_primary
    when "lodgings"
      lodgings_menu_items
    end
  end

  def tertiary_items
    nil
  end

  private

  def lodgings_menu_items
    [
      {
        body: "Hébergements de groupes",
        url: lodgings_path,
        active: @active_secondary == "lodgings"
      },
      {
        body: "Chambres",
        url: rooms_path,
        active: @active_secondary == "rooms"
      }
    ]
  end
end
