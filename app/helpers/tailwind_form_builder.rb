class TailwindFormBuilder < ActionView::Helpers::FormBuilder
  attr_reader :template, :options, :object_name

  def group(&)
    tag.div class: 'mt-5 grid grid-cols-1 gap-6', &
  end

  def actions(&)
    tag.div class: 'mt-10 flex justify-end space-x-4 text-right', &
  end

  def submit(title)
    render Button::Component.new(type: :submit, title:)
  end

  def check_box(method, opts={})
    default_opts = { class: "w-4 h-4 bg-gray-50 rounded border border-gr-300 focus:ring-3 focus:ring-blue-300 dark:bg-gray-700 dark:border-gray-600 dark:focus:ring-blue-600 dark:ring-offset-gray-800" }
    merged_opts = default_opts.merge(opts)
    super(method, merged_opts)
  end

  def check_input(name, *args, &block)
    options = args.extract_options!
    message = options.fetch(:message, errors(name))
    error = options.fetch(:error, any_errors?(name))

    @template.content_tag(:div, class: 'relative flex items-start', id: "field-#{name}") do
      @template.concat(@template.content_tag(:div, { class: 'flex h-5 items-center' }) do
        @template.concat(check_box(name, {class: 'h-4 w-4 rounded border-gray-500 text-indigo-600 focus:ring-indigo-500' + (error ? ' invalid-input' : '') }.merge(options)))
      end)
      @template.concat(@template.content_tag(:div, { class: 'ml-3 text-sm' }) do
        @template.concat(label(name, label_text(name, options), { class: 'font-medium text-gray-900' }))
        @template.concat(hint_message(message, error))
      end)
    end
  end

  def collection_check_boxes(method, collection, value_method, text_method, options = {}, html_options = {}, &block)
    super(
      method,
      collection,
      value_method,
      text_method,
      options,
      html_options,
      &block
    )
  end

  def collection_radio_buttons(method, collection, value_method, text_method, options = {}, html_options = {}, &block)
    super(
      method,
      collection,
      value_method,
      text_method,
      options,
      html_options.reverse_merge(class: "focus:ring-indigo-500 h-4 w-4 text-indigo-600 border-gray-300"),
      &block
    )
  end

  def email_field(name, *args, &block)
    args[0].merge!({ type: 'email' }) if args.any?
    text_field(name, *args, &block)
  end

  def label(attribute_name, *args, &block)
    options = args.extract_options!.dup

    default_class = "block text-sm font-medium text-gray-700"
    options = arguments_with_updated_default_class(default_class, **options)

    super(attribute_name, *[args.first, options], &block)
  end

  def text_field(method, options = {}) # rubocop:disable Style/OptionHash
    # default_options = { class: input_html_classes(method) }
    # default_options[:class] << (options[:maxlength] ? 'w-20' : 'w-full')
    # merged_options = default_options.merge(options)
    merged_options = arguments_with_updated_default_class(
      input_html_classes(method), **options
    )
    hint = options.fetch(:hint, errors(method))
    error = options.fetch(:error, any_errors?(method))

    tag.div class: 'form-control' do
      label(method, class: 'label mb-1') do
        tag.span(label_text(method, merged_options), class: 'label-text')
      end + super(method, merged_options) + hint_message(hint, error)
      # end + super(method, merged_options) + hint_message(hint, error) + errors(method)
    end
  end

  def number_field(name, *args, &block)
    args[0].merge!({ type: 'number' }) if args.any?
    text_field(name, *args, &block)
  end

  def password_field(method, options = {}) # rubocop:disable Style/OptionHash
    default_options = { class: input_html_classes(method) }
    default_options[:class] << (options[:maxlength] ? 'w-20' : 'w-full')
    merged_options = default_options.merge(options)

    tag.div class: 'form-control' do
      label(method, class: 'label') do
        tag.span(label_text(method, merged_options), class: 'label-text')
      end + super(method, merged_options) + errors(method)
    end
  end

  def date_field(method, options = {}) # rubocop:disable Style/OptionHash
    default_options = { class: input_html_classes(method) }
    default_options[:class]['w-full'] = 'w-48'
    default_options[:class]['text-sm'] = 'text-lg'
    merged_options = default_options.merge(options)

    tag.div class: 'form-control' do
      label(method, class: 'label') do
        tag.span(label_text(method, merged_options), class: 'label-text')
      end + super(method, merged_options) + errors(method)
    end
  end

  def collection_select_field(name, collection, value_method, text_method, options = {}, html_options = {})
    html_options = arguments_with_updated_default_class(
      "mt-1 block w-full rounded-md border-gray-500 py-2 pl-3 pr-10 text-base focus:border-indigo-500 focus:outline-none focus:ring-indigo-500 sm:text-sm", **html_options
    )
    collection_select(name, collection, value_method, text_method, options, html_options)
  end

  def select(method, choices = nil, options = {}, html_options = {}, &block)
    super(
      method,
      choices,
      options,
      html_options,
      &block
    )
  end

  def text_area(name, *args, &block)
    args[0].merge!({ class: 'block w-full rounded-md border-gray-500 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm' }) if args.any?
    super(name, *args, &block)
  end

  # def radio_buttons(method, options = {})
  #   default_options = { class: input_html_classes(method) }
  #   default_options[:class] << 'w-full'
  #   merged_options = default_options.merge(options)
  #
  #   tag.div class: 'sm:col-span-2' do
  #     tag.div class: 'max-w-lg' do
  #       tag.p(hint(method, merged_options), class: 'text-sm text-gray-500')
  #       tag.div class: 'mt-4 space-y-4' do
  #
  #       end
  #     end
  #   end
  # end

  private

  delegate :tag, :link_to, :safe_join, :render, to: :template

  def any_errors?(name)
    return false unless object&.errors
    object.errors[name].any?
  end

  # This helper can be used to define a default set of CSS classes but replace / remove some of them when needed.
  # The <tt>default_class</tt> argument defines the initial set of (default) classes.
  # The helper then recognizes two parameters in the keyword arguments:
  # * <tt>remove_default_class</tt> - class(es) in this parameter will be removed from the default set of classes
  # * <tt>class</tt> - class(es) in this parameter will be appended to the resulting set of classes
  # So, in essence, this helper does the following:
  #
  # <tt>class = default_class - remove_default_class + class</tt>
  #
  # For example, this link with normally defined (default) classes, which resides in a method:
  #
  #  def users_link
  #    link_to "Users", users_path, class: "font-bold text-lg"
  #  end
  # supports calling <tt>users_link</tt> and renders <tt>&lt;a class="font-bold text-lg" href="/users">Users&lt;/a></tt>.
  #
  # If we want to allow overriding some of the default classes, we can use this helper in the method:
  #
  #  def users_link(**kwargs)
  #    link_to "Users", users_path, **arguments_with_updated_default_class("font-bold text-lg", **kwargs)
  #  end
  #
  # Now, while the default call (<tt>users_link</tt>) renders the same default output, we can override the classes now
  # using <tt>users_link(remove_default_class: "text-lg", class: "text-sm")</tt>.
  # This renders <tt>&lt;a class="font-bold text-sm" href="/users">Users&lt;/a></tt> instead.
  #
  # The helper also supports prefixed class arguments which allow multiple class arguments to be removed / replaced.
  # E.g. with the following prefix paremeter set <tt>prefix: "form"</tt>, the helper will replace default classes,
  # expecting the <tt>remove_default_form_class</tt> and <tt>form_class</tt> parameters to be present to work with.
  def arguments_with_updated_default_class(default_class, prefix: nil, **kwargs)
    kwargs = kwargs.dup
    classes = default_class.to_s
    prefix = "#{prefix}_" if prefix

    remove_key = :"remove_default_#{prefix}class"
    class_key = :"#{prefix}class"

    if kwargs[remove_key].present?
      classes = (classes.split - kwargs[remove_key].split).join(" ")
      kwargs.delete(remove_key)
    end

    # simple_form sometimes uses array of classes instead of strings
    kwargs[class_key] = kwargs[class_key].map(&:to_s).join(" ") if kwargs[class_key].is_a?(Array)

    kwargs[class_key] = (classes.split + kwargs[class_key].to_s.split).join(" ")
    kwargs
  end

  def hint_message(message, error)
    return unless message.present?

    tag.p class: 'text-sm text-gray-500 ' + (error ? 'hint-error' : 'hint') do
      message
    end
  end

  def input_html_classes(method)
    ['block w-full rounded-md border-gray-500 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm rounded-md', ('border-red-300 text-red-900 placeholder-red-300 focus:border-red-500 focus:outline-none focus:ring-red-500' if object.errors[method].present?)].join
  end

  def label_text(method, options)
    options.fetch(:label, object.class.human_attribute_name(method))
  end

  def errors(method)
    return if object.errors[method].blank?

    tag.ul class: 'mt-2 text-sm text-red-500' do
      safe_join(object.errors[method].map { |error| tag.li(error) })
    end
  end
end

# The Rails default is wrapping the error field into <div class="fields_with_error">...</div>
# This makes styling complicated, so just render the plain html tag.
# Error handling is done by `input_html_classes`.
ActionView::Base.field_error_proc = proc { |html_tag, _instance| html_tag }
