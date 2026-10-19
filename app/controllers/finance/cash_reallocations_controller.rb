module Finance
  # Modifier la ventilation d'une ligne déjà affectée (Michael, 2026-10-19).
  #
  # Toutes les parts de la ligne sur un écran : on change un compte, un pôle,
  # une entité, un montant, on ajoute ou on retire une part, et on enregistre
  # une fois. Le travail se fait dans `Finance::ReallocateCashEntry` : la
  # contre-passation d'une ligne comptabilisée, puis sa nouvelle passation.
  class CashReallocationsController < Finance::AccountingBaseController
    before_action :get_entry
    breadcrumb "Trésorerie", :finance_cash_entries_path, match: :exact

    def edit
      @allocations = @entry.cash_allocations.includes(:document).ordered.to_a
      preparer_ecran
    end

    def update
      resultat = Finance::ReallocateCashEntry.new(cash_entry: @entry, parts: parts_params,
                                                  whodunnit: current_user&.email).run!
      redirect_to finance_cash_entry_path(@entry), notice: message(resultat)
    rescue Finance::ReallocateCashEntry::Refused, Accounting::PostDocument::MissingFiscalYear,
           Accounting::PostCashEntry::TooManyEntities, Accounting::PostCashEntry::NotPostable => e
      # Ce qu'on vient de saisir se réaffiche tel quel, avec la raison du refus :
      # tout retaper pour une part de travers décourage la correction.
      @entry.reload
      @allocations = parts_saisies
      preparer_ecran
      flash.now[:alert] = e.message
      render :edit, status: :unprocessable_entity
    end

    private

    def get_entry = @entry = CashEntry.find(params[:cash_entry_id])

    def preparer_ecran
      breadcrumb @entry.label, finance_cash_entry_path(@entry), match: :exact
      breadcrumb "Modifier la ventilation", edit_finance_cash_entry_reallocation_path(@entry), match: :exact

      # Les listes du formulaire d'affectation, plus les comptes et entités que
      # la ligne porte déjà : un compte désactivé depuis ne doit pas disparaître
      # de sa part en silence à l'enregistrement.
      @general_accounts = GeneralAccount.actives.or(GeneralAccount.where(id: @allocations.map(&:general_account_id))).ordered
      @teams = Team.ordered
      @entities = LegalEntity.actives.or(LegalEntity.where(id: @allocations.map(&:legal_entity_id))).ordered
    end

    def message(resultat)
      return "Rien n'a changé." unless resultat.changed

      debut = resultat.was_posted ? "Ventilation modifiée : l'ancienne écriture est contre-passée" : "Ventilation modifiée"
      if resultat.posted
        resultat.was_posted ? "#{debut}, la nouvelle est au grand livre." : "#{debut} et ligne comptabilisée."
      elsif resultat.remaining_cents == @entry.amount_cents
        "#{debut}. Plus rien n'est affecté : la ligne retourne dans « À affecter »."
      else
        "#{debut}. Il reste #{Money.new(resultat.remaining_cents, 'EUR').format} à affecter."
      end
    end

    # Les parts arrivent sous `parts[clé]`, dans l'ordre de l'écran ; une part
    # existante porte son `id`. Une part ajoutée puis laissée vide (ni compte
    # ni montant) n'est pas une part.
    def parts_params
      brutes = params[:parts].respond_to?(:values) ? params[:parts].values : []
      brutes.map { |part| part_attributes(part) }
            .reject { |part| part[:id].blank? && part[:general_account_id].blank? && part[:amount_cents].nil? }
    end

    def part_attributes(part)
      permitted = part.permit(:id, :general_account_id, :team_id, :legal_entity_id, :amount)
      amount = permitted.delete(:amount)
      permitted[:amount_cents] = amount.present? ? Monetize.parse(amount.to_s).cents : nil
      permitted[:team_id] = permitted[:team_id].presence
      permitted.to_h.symbolize_keys
    end

    # La saisie refusée, en parts non enregistrées : une part existante garde sa
    # pièce, une nouvelle n'en a pas.
    def parts_saisies
      existantes = @entry.cash_allocations.includes(:document).index_by(&:id)
      parts_params.map do |part|
        attributs = part.except(:id)
        allocation = existantes[part[:id].to_i] if part[:id].present?
        allocation ? allocation.tap { |a| a.assign_attributes(attributs) } : CashAllocation.new(attributs)
      end
    end
  end
end
