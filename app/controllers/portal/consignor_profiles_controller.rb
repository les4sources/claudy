module Portal
  # Ce qui figure en tête de la feuille de l'artisan (epic #359, phase 3) : sa
  # photo et une phrase de présentation. Il les règle lui-même.
  class ConsignorProfilesController < Portal::BaseController
    before_action :require_portal_consignor

    def edit
      @consignor = current_portal_consignor
    end

    def update
      @consignor = current_portal_consignor
      @consignor.tagline = params.dig(:consignor, :tagline).to_s.strip.presence
      portrait = params.dig(:consignor, :portrait)
      @consignor.portrait.attach(portrait) if portrait.present?

      if @consignor.save
        redirect_to portal_consignments_path, notice: "Votre feuille est à jour."
      else
        render :edit, status: :unprocessable_entity
      end
    end
  end
end
