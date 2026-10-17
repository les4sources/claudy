module Finance
  # Le guide de la comptabilité (Michael, 2026-10-17) : le circuit de l'argent,
  # la routine et le lexique, pour la personne qui démarre. Le texte vit dans
  # `Finance::Guide`, que l'aide de chaque écran lit aussi.
  class GuideController < Finance::AccountingBaseController
    breadcrumb "Guide", :finance_guide_path, match: :exact

    def show
      @circuit = Finance::Guide::CIRCUIT
      @routine = Finance::Guide::ROUTINE
      @terms = Finance::Guide.terms
    end
  end
end
