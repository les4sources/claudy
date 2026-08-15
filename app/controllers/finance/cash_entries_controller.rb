module Finance
  # Le journal de trésorerie (issue #179).
  #
  # L'écran « À affecter » est le cœur du dispositif : son compteur doit pouvoir
  # tomber à zéro à la fin d'un mois. C'est le seul indicateur qui dit, en un
  # coup d'œil, si la comptabilité est à jour — et il remplace des heures de
  # rapprochement annuel par un geste mensuel.
  class CashEntriesController < Finance::BaseController
    before_action :get_entry, only: [:show, :edit, :update, :post_entry, :unpost, :exclude, :ventilate]

    breadcrumb "Comptabilité", :finance_accounting_path, match: :exact
    breadcrumb "Trésorerie", :finance_cash_entries_path, match: :exact

    def index
      @accounts = CashAccount.ordered
      @account = CashAccount.find_by(id: params[:cash_account_id])
      @status = params[:status].presence
      @from = parsed_date(params[:from]) || Date.current.beginning_of_year
      @to = parsed_date(params[:to]) || Date.current.end_of_year

      scope = CashEntry.ordered.in_period(@from, @to).includes(:cash_account, :cash_allocations)
      scope = scope.where(cash_account_id: @account.id) if @account
      scope = scope.where(status: @status) if @status
      @entries = scope.to_a

      @pending_count = CashEntry.pending.count
      @pending_cents = CashEntry.pending.sum(:amount_cents)
    end

    # L'écran de travail : ce qui reste à affecter, et rien d'autre.
    def unallocated
      # Les suggestions se recalculent à l'ouverture de l'écran : c'est le seul
      # moment où elles servent, et ça évite un job de fond que l'application
      # n'a pas les moyens de garantir.
      Finance::SuggestAllocations.new(whodunnit: current_user&.email).run!

      @entries = CashEntry.pending.ordered.includes(:cash_account, :cash_allocations, :allocation_suggestions)

      # Le rapprochement de séjour se calcule à l'affichage : il dépend de
      # l'état des soldes, qui bouge à chaque paiement.
      @stay_matches = @entries.each_with_object({}) do |entry, hash|
        next if entry.cash_allocations.any?

        correspondance = Finance::MatchStay.new(cash_entry: entry).run!
        next if correspondance.nil?

        lignes = begin
          Finance::VentilateStay.new(stay: correspondance.stay, amount_cents: entry.amount_cents).run!
        rescue Finance::VentilateStay::EmptyQuote, Finance::VentilateStay::MissingMapping
          nil
        end
        next if lignes.blank?

        hash[entry.id] = { match: correspondance, lines: lignes }
      end
      @general_accounts = GeneralAccount.actives.ordered
      @teams = Team.ordered
      @entities = LegalEntity.actives.ordered
    end

    def show
      breadcrumb @entry.label, finance_cash_entry_path(@entry), match: :exact

      @allocations = @entry.cash_allocations.includes(:general_account, :team, :legal_entity).ordered
      @allocation = CashAllocation.new(amount_cents: @entry.remaining_cents)
      @general_accounts = GeneralAccount.actives.ordered
      @teams = Team.ordered
      @entities = LegalEntity.actives.ordered
    end

    def new
      @entry = CashEntry.new(entry_date: Date.current)
      @accounts = CashAccount.actives.ordered
    end

    def create
      @entry = CashEntry.new(entry_params)

      if @entry.save
        redirect_to finance_cash_entry_path(@entry), notice: "Ligne de trésorerie créée."
      else
        @accounts = CashAccount.actives.ordered
        flash.now[:alert] = @entry.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @accounts = CashAccount.actives.ordered
    end

    def update
      if @entry.update(entry_params)
        redirect_to finance_cash_entry_path(@entry), notice: "Ligne mise à jour."
      else
        @accounts = CashAccount.actives.ordered
        flash.now[:alert] = @entry.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    # Ventiler un séjour : les lignes viennent du devis reconstruit, la base est
    # l'argent reçu, et c'est un humain qui déclenche. L'IBAN du tiers est
    # mémorisé pour ce client — c'est ce qui fera que le prochain virement se
    # rapprochera tout seul.
    def ventilate
      stay = Stay.find(params[:stay_id])
      entite = @entry.cash_account.legal_entity
      lignes = []

      # Tout dans la MÊME transaction : une ventilation créée sans son écriture
      # comptable, ou sans l'IBAN appris, laisserait un état incohérent derrière
      # une réponse d'échec.
      ApplicationRecord.transaction do
        @entry.lock!

        # La ventilation se calcule APRÈS le verrou : calculée avant, elle
        # totaliserait un montant que la ligne n'a peut-être plus.
        lignes = Finance::VentilateStay.new(stay: stay, amount_cents: @entry.reload.amount_cents).run!

        lignes.each do |ligne|
          @entry.cash_allocations.create!(
            general_account: ligne.general_account,
            team: ligne.team,
            legal_entity: entite,
            amount_cents: ligne.amount_cents,
            document: stay,
            label: ligne.label
          )
        end

        CustomerBankAccount.remember!(customer: stay.customer, iban: @entry.counterparty_iban,
                                      holder_name: @entry.counterparty_name)

        if @entry.reload.fully_allocated?
          Accounting::PostCashEntry.new(cash_entry: @entry, whodunnit: current_user&.email).run!
        end
      end

      redirect_to finance_cash_entry_path(@entry),
                  notice: "Séjour ##{stay.id} ventilé en #{lignes.size} ligne(s) — l'IBAN est mémorisé pour ce client."
    rescue Finance::VentilateStay::EmptyQuote, Finance::VentilateStay::MissingMapping,
           Accounting::PostDocument::MissingFiscalYear => e
      redirect_to finance_cash_entry_path(@entry), alert: e.message
    end

    def post_entry
      Accounting::PostCashEntry.new(cash_entry: @entry, whodunnit: current_user&.email).run!
      redirect_to finance_cash_entry_path(@entry), notice: "Ligne comptabilisée — l'écriture est au grand livre."
    rescue Accounting::PostCashEntry::NotFullyAllocated, Accounting::PostCashEntry::AlreadyPosted,
           Accounting::PostDocument::MissingFiscalYear => e
      redirect_to finance_cash_entry_path(@entry), alert: e.message
    end

    def unpost
      Accounting::UnpostCashEntry.new(cash_entry: @entry, whodunnit: current_user&.email).run!
      redirect_to finance_cash_entry_path(@entry),
                  notice: "Passation annulée — l'écriture a été contre-passée, la ligne est réaffectable."
    rescue Accounting::UnpostCashEntry::NotPosted => e
      redirect_to finance_cash_entry_path(@entry), alert: e.message
    end

    def exclude
      motif = params[:reason].presence
      if motif.blank?
        return redirect_to finance_cash_entry_path(@entry),
                           alert: "Une exclusion demande un motif — c'est ce qui la rend relisible plus tard."
      end

      @entry.exclude!(motif)
      redirect_to finance_cash_entry_path(@entry), notice: "Ligne exclue : #{motif}"
    end

    private

    def get_entry = @entry = CashEntry.find(params[:id])
    def finance_secondary = "accounting"

    def entry_params
      permitted = params.require(:cash_entry).permit(:cash_account_id, :entry_date, :value_date, :label,
                                                     :counterparty_name, :counterparty_iban, :communication,
                                                     :external_ref, :statement_ref, :amount)
      amount = permitted.delete(:amount)
      permitted[:amount_cents] = Monetize.parse(amount.to_s).cents if amount.present?
      permitted
    end

    def parsed_date(raw)
      raw.present? ? Date.parse(raw) : nil
    rescue Date::Error
      nil
    end
  end
end
