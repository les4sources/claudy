module Finance
  # La Situation financière (Michael, 2026-11-12) : la page des administrateurs,
  # sortie de la Comptabilité pour que chacun ait la sienne. Les comptables
  # travaillent en Comptabilité (« À faire »), les Sourciers lisent ici comment
  # va chaque structure, ce qui l'attend et ce qu'il faut trancher ensemble.
  #
  # Réservée aux Sourciers (`Access::EXCLUSIVE`), et à la nouvelle interface :
  # tous les chiffres viennent de `Finance::Overview`, qui lit les briques
  # existantes ; cette page n'en calcule aucun.
  class SituationController < ::BaseController
    access_section :situation
    breadcrumb "Situation financière", :finance_situation_path, match: :exact

    def show
      return render("finance/situation/old_interface") unless current_user.new_interface?

      @loans = Finance::Loans.new
      @verdicts = Finance::SpendingVerdict.for_all(loans: @loans)
      @overview = Finance::Overview.new(loans: @loans, verdicts: @verdicts)
      @focus = @overview.find(params[:entity]) if params[:entity].present?
      @healths = @focus ? [@focus] : @overview.entities
      @signals = @overview.signals(only: @focus)
      @reliability = Finance::Reliability.new
      @page_guide_inline = true
    end

    # Le détail d'un montant de « Peut-on dépenser ? », en fenêtre : la même
    # vue que celle de la Comptabilité, dont les liens vers les écrans de
    # compta ne s'ouvrent qu'à qui peut les lire (`situation_link_to`).
    def verdict_detail
      @part = params[:part]
      @verdict = Finance::SpendingVerdict.new(legal_entity: LegalEntity.actives.find(params[:legal_entity_id]))
      render "finance/accounting/verdict_detail", layout: "modal"
    end

    private

    def set_presenters
      @menu_presenter = Components::MenuPresenter.new(active_primary: "situation")
      @situation_view = true
    end
  end
end
