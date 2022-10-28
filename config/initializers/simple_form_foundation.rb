module SimpleForm
  module Components
    module Errors
      def error(wrapper_options = nil)
        # always load provided error message (for Foundation Abide validation)
        error_text
      end
    end
  end
end

# Use this setup block to configure all options available in SimpleForm.
SimpleForm.setup do |config|
  config.wrappers :foundation, tag: 'div', class: 'field' do |b|
    b.use :html5
    b.optional :pattern
    b.use :placeholder
    b.wrapper tag: :label, error_class: 'is-invalid-label' do |ba|
      ba.use :label_text, wrap_with: { tag: :span, class: "label-text" }
      ba.use :hint,  wrap_with: { tag: :p, class: "help-text" }
      ba.use :input
      ba.use :error, wrap_with: { tag: :span, class: "form-error animated fadeInDown" }
    end
  end

  config.wrappers :hint_below, tag: 'div', class: 'field' do |b|
    b.use :html5
    b.optional :pattern
    b.use :placeholder
    b.wrapper tag: :label, error_class: 'is-invalid-label' do |ba|
      ba.use :label_text, wrap_with: { tag: :span, class: "label-text" }
      ba.use :input
      ba.use :error, wrap_with: { tag: :span, class: "form-error animated fadeInDown" }
      ba.use :hint,  wrap_with: { tag: :p, class: "help-text" }
    end
  end

  config.wrappers :foundation_pickadate, tag: 'div', class: 'field' do |b|
    b.use :html5
    b.optional :pattern
    b.use :placeholder
    b.wrapper tag: :label, error_class: 'is-invalid-label' do |ba|
      ba.use :label_text, wrap_with: { tag: :span, class: "label-text" }
      ba.use :hint,  wrap_with: { tag: :p, class: "help-text" }
      ba.use :input
      ba.use :error, wrap_with: { tag: :span, class: "form-error animated fadeInDown" }
    end
    b.wrapper tag: :div, class: "pickadate-container" do; end
  end

  config.wrappers :foundation_append, tag: 'div', class: 'field' do |b|
    b.use :html5
    b.optional :pattern
    b.use :placeholder
    b.wrapper tag: :label, error_class: 'is-invalid-label' do |ba|
      ba.use :label_text, wrap_with: { tag: :span, class: "label-text" }
      ba.wrapper tag: :div, class: "input-group" do |append|
        append.use :input
      end
      ba.use :error, wrap_with: { tag: :span, class: "form-error animated fadeInDown" }
      ba.use :hint,  wrap_with: { tag: :p, class: 'help-text' }
    end
  end

  config.wrappers :foundation_wysiwyg, tag: 'div', class: 'field' do |b|
    b.use :html5
    b.optional :pattern
    b.use :placeholder
    b.wrapper tag: :div, error_class: 'is-invalid-label' do |ba|
      ba.optional :label, wrap_with: { tag: :span, class: 'label-text' }
      ba.use :hint,  wrap_with: { tag: :p, class: 'help-text' }
    # end
    # b.wrapper tag: :div, error_class: 'is-invalid-label' do |ba|
      ba.use :input
      ba.use :error, wrap_with: { tag: :span, class: 'form-error animated fadeInDown' }
    end
  end

  config.wrappers :foundation_checkbox, class: 'field' do |b|
    b.use :html5
    b.optional :pattern
    b.optional :readonly

    b.wrapper tag: :label do |ba|
      ba.wrapper tag: :div, class: 'grid-x' do |bb|
        bb.wrapper tag: :div, class: 'cell shrink' do |bc|
          bc.use :input
          bc.wrapper tag: :span, class: 'custom-checkbox' do |bd|
          end
        end
        bb.wrapper tag: :div, class: 'cell auto' do |bc|
          bc.use :label_text, wrap_with: { tag: :span, class: 'checkbox-label' }
          bc.use :error, wrap_with: { tag: :small, class: 'form-error animated fadeInDown' }
          bc.use :hint, wrap_with: { tag: :p, class: 'help-text' }
        end
      end
    end
  end

  config.wrappers :foundation_card_switch, class: 'field' do |b|
    b.use :html5
    b.optional :pattern
    b.optional :readonly

    b.wrapper tag: :label do |ba|
      ba.wrapper tag: :div, class: 'grid-x row align-top align-center' do |bb|
        bb.wrapper tag: :div, class: 'cell small-12 columns' do |bc|
          bc.wrapper tag: :div, class: 'switch' do |bd|
            bd.use :input, class: 'switch-input'
            bd.use :label, class: 'switch-paddle'
            # not working on Edge:
            # bd.wrapper tag: :label, class: 'switch-paddle' do |be|
            #   be.use :label_text, wrap_with: { tag: :span, class: 'show-for-sr' }
            # end
          end
        end
      end
    end
  end

  config.wrappers :foundation_switch, class: 'field' do |b|
    b.use :html5
    b.optional :pattern
    b.optional :readonly

    b.wrapper tag: :label do |ba|
      ba.wrapper tag: :div, class: 'grid-x row align-top' do |bb|
        bb.wrapper tag: :div, class: 'cell shrink columns' do |bc|
          bc.wrapper tag: :div, class: 'switch' do |bd|
            bd.use :input, class: 'switch-input'
            bd.use :label, class: 'switch-paddle'
            # not working on Edge:
            # bd.wrapper tag: :label, class: 'switch-paddle' do |be|
            #   be.use :label_text, wrap_with: { tag: :span, class: 'show-for-sr' }
            # end
          end
        end
        bb.wrapper tag: :div, class: 'cell auto columns switch-label' do |bc|
          bc.use :label_text
          bc.use :error, wrap_with: { tag: :small, class: 'form-error animated fadeInDown' }
          bc.use :hint, wrap_with: { tag: :p, class: 'help-text' }
        end
      end
    end
  end

  config.wrappers :foundation_segmented_selector, class: 'field' do |b|
    b.use :html5
    b.optional :pattern
    b.optional :readonly

    b.wrapper tag: :label do |ba|
      ba.use :label_text, wrap_with: { tag: :span, class: 'label-text' }
      ba.wrapper tag: :ul, class: 'segmented-control' do |segmented_control|
        segmented_control.use :input
      end
      ba.use :error, wrap_with: { tag: :small, class: 'form-error animated fadeInDown' }
      ba.use :hint, wrap_with: { tag: :p, class: 'help-text' }
    end
  end

  config.wrappers :foundation_radio_buttons, class: 'field' do |b|
    b.use :html5
    b.optional :pattern
    b.optional :readonly

    b.wrapper tag: :label do |ba|
      ba.use :label_text, wrap_with: { tag: :span, class: 'label-text' }
      ba.use :hint, wrap_with: { tag: :p, class: 'help-text' }
    end
    b.use :input
    b.use :error, wrap_with: { tag: :small, class: 'form-error animated fadeInDown' }
  end
end
