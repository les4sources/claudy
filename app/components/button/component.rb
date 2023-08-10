class Button::Component < ViewComponent::Base
  # rubocop:disable Style/MultilineMethodSignature, Metrics/ParameterLists
  def initialize(
    path: nil,
    title: nil,
    icon: nil,
    type: :link,
    style: :primary,
    options: {}
  )
    # rubocop:enable Style/MultilineMethodSignature, Metrics/ParameterLists
    super

    if title.nil? && icon.nil?
      # :nocov:
      raise ArgumentError,
            'You must provide either a title or an icon (or both)'
      # :nocov:
    end

    @path = path
    @title = title
    @icon = icon
    @type = type
    @style = style
    @options = options
  end

  attr_reader :path, :title, :icon, :style, :options

  def method
    case @type
    when :link
      :link_to
    when :button
      :button_to
    when :submit
      :button_tag
    else
      # :nocov:
      raise ArgumentError, 'Type must be :link, :button or :submit'
      # :nocov:
    end
  end

  def btn_class
    case style
    when :primary
      btn_primary_class
    when :secondary
      btn_secondary_class
    when :hollow
      btn_hollow_class
    when :inline
      btn_inline_class
    end
  end

  def btn_primary_class
    %w[
      inline-flex
      items-center
      py-2
      border
      border-transparent
      rounded
      focus:outline-none
      focus:ring-2
      focus:ring-offset-2
      focus:ring-green-500
      transition
      text-white
      bg-green-600
      hover:bg-green-700
      shadow-sm
      px-3
      hover:scale-105
    ]
  end

  def btn_secondary_class
    %w[
      inline-flex
      items-center
      rounded-md
      border
      border-transparent
      bg-indigo-600
      px-4
      py-2
      text-sm
      font-medium
      text-white
      shadow-sm
      hover:bg-indigo-700
      focus:outline-none
      focus:ring-2
      focus:ring-indigo-500
      focus:ring-offset-2
      transition
      hover:scale-105
    ]
  end

  def btn_hollow_class
    %w[
      inline-flex
      items-center
      rounded-md
      border
      border-gray-300
      bg-white
      px-4
      py-2
      text-sm
      font-medium
      text-gray-700
      shadow-sm
      hover:bg-gray-50
      focus:outline-none
      focus:ring-2
      focus:ring-indigo-500
      focus:ring-offset-2
    ]
  end

  def btn_inline_class
    %w[
      mt-3 
      inline-flex 
      w-full 
      items-center 
      justify-center 
      rounded-md 
      bg-indigo-600 
      px-3 
      py-2 
      text-sm 
      font-semibold 
      text-white 
      shadow-sm 
      hover:bg-indigo-500 
      focus-visible:outline 
      focus-visible:outline-2 
      focus-visible:outline-offset-2 
      focus-visible:outline-indigo-600 
      sm:ml-3 
      sm:mt-0 
      sm:w-auto
    ]
  end

  def icon_name
    icon.is_a?(Hash) ? icon.fetch(:name) : icon
  end

  def icon_class
    "fa fa-#{icon_name} w-8 h-8"
  end
end
