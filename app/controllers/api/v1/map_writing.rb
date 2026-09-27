module Api
  module V1
    # Ce que partagent les écritures de la carte et des plantes (epic #348,
    # phase 8) : les listes fermées, les fenêtres de récolte et le rendu des 422.
    #
    # Une liste fermée accepte la clé (`existing`) OU le libellé de la base Notion
    # (« Existante », casse ignorée) : l'import reprend les valeurs Notion telles
    # quelles. Une valeur inconnue donne un 422 qui liste les clés admises, jamais
    # un « n'est pas inclus(e) dans la liste » muet.
    module MapWriting
      extend ActiveSupport::Concern

      included do
        rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
      end

      private

      def render_record_invalid(exception)
        render_invalid(exception.record)
      end

      def render_errors(messages)
        render json: { error: "unprocessable_entity", messages: Array(messages) }, status: :unprocessable_entity
      end

      # La clé de `choices` qui correspond à `value` (clé ou libellé), ou nil
      # après avoir ajouté un message à `errors`. Une valeur vide passe telle quelle.
      def closed_value(field, value, choices, errors)
        return nil if value.blank?

        text = value.to_s.squish
        return text if choices.key?(text)

        key = choices.find { |_, label| label.to_s.casecmp?(text) }&.first
        return key if key

        errors << "#{field} « #{text} » n'est pas une valeur admise (valeurs admises : #{choices.keys.join(', ')})"
        nil
      end

      # `harvest_windows` du corps : nil s'il est absent (on ne touche à rien),
      # sinon une liste de `{ "part" => clé, "months" => [entiers] }`.
      def harvest_windows_param(root, errors)
        body = params[root]
        return nil unless body.respond_to?(:key?) && body.key?(:harvest_windows)

        Array(body[:harvest_windows]).filter_map do |window|
          unless window.respond_to?(:permit)
            errors << "harvest_windows attend une liste d'objets { part, months }"
            next
          end

          window = window.permit(:part, months: [])
          part = closed_value("harvest_windows.part", window[:part], PlantHarvestWindow::PARTS, errors)
          errors << "harvest_windows.part est obligatoire" if window[:part].blank?
          { "part" => part, "months" => Array(window[:months]) } if part
        end
      end

      # Remplace les fenêtres PROPRES du porteur. Une liste vide les efface : une
      # plante revient alors aux fenêtres de son espèce.
      def replace_harvest_windows!(owner, windows)
        return if windows.nil?

        owner.harvest_windows.destroy_all
        windows.each { |window| owner.harvest_windows.create!(window) }
        owner.harvest_windows.reset
      end
    end
  end
end
