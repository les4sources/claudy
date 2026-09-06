module Kitchen
  # Paramètres > Cuisine (epic #219, phase 2) : quelles familles sont proposées,
  # qui s'en charge par défaut, à partir de quel nombre de convives et de quel
  # délai on prévient. Un seul formulaire, une sauvegarde en bloc.
  class SettingsController < BaseController
    breadcrumb "Cuisine", :kitchen_settings_path, match: :exact

    FAMILY_FIELDS = %w[default_human_id max_people lead_days].freeze

    def show
      @humans = assignable_humans
    end

    def update
      Kitchen::Config.family_keys.each do |family|
        attrs = params.dig(:kitchen, family) || {}
        Setting.set("kitchen.#{family}.enabled", attrs[:enabled] == "1" ? "1" : "0")
        FAMILY_FIELDS.each do |field|
          Setting.set("kitchen.#{family}.#{field}", attrs[field].to_s.strip)
        end
      end
      Setting.set("kitchen.coordinator_email", params.dig(:kitchen, :coordinator_email).to_s.strip)

      redirect_to kitchen_settings_path, notice: "Les paramètres de la cuisine ont été enregistrés."
    end

    private

    def assignable_humans
      Human.where(status: "active").order(:name)
    end

    def set_presenters
      @settings_view = true
    end
  end
end
