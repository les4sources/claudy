module Finance
  # Le journal de trésorerie (issue #179).
  #
  # L'écran « À affecter » est le cœur du dispositif : son compteur doit pouvoir
  # tomber à zéro à la fin d'un mois. C'est le seul indicateur qui dit, en un
  # coup d'œil, si la comptabilité est à jour — et il remplace des heures de
  # rapprochement annuel par un geste mensuel.
  class CashEntriesController < Finance::AccountingBaseController
    before_action :get_entry,
                  only: [:show, :edit, :update, :post_entry, :unpost, :exclude, :ventilate, :payout,
                         :pay_invoice, :pay_expense_report, :reconcile_payout, :settle]
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
    # Cet écran est une FILE D'ATTENTE : on y traite quelques lignes, pas dix
    # mille. Il faisait pourtant, pour CHAQUE ligne en attente, un rapprochement
    # de séjour qui coûte plus d'une seconde. Tant que le journal tenait en une
    # poignée de lignes, personne ne l'a vu ; à 10 133 lignes reprises, l'écran
    # demandait plus de trois heures et tombait en timeout.
    #
    # Tout le travail est donc borné à la PAGE affichée. Le compteur, lui, reste
    # global : savoir combien de lignes attendent est l'information la plus utile
    # de cet écran, et elle ne coûte qu'un COUNT.
    PAR_PAGE = 25

    def unallocated
      @pending_total = CashEntry.pending.count

      # La file se restreint à un compte, ou à une famille de comptes : l'arrêté
      # du mois renvoie ici filtré sur Stripe quand une recette Stripe attend sa
      # correspondance de catégorie (epic #250). Sans filtre, on retombe sur la
      # file entière — comportement inchangé.
      scope = CashEntry.pending.ordered
      scope = scope.where(cash_account_id: params[:cash_account_id]) if params[:cash_account_id].present?
      if params[:kind].present? && CashAccount::KINDS.include?(params[:kind])
        scope = scope.where(cash_account_id: CashAccount.where(kind: params[:kind]).select(:id))
      end
      @filtered_total = scope.count
      @filter_kind = params[:kind].presence
      @filter_account = CashAccount.find_by(id: params[:cash_account_id])

      @entries = scope.includes(:cash_account, :cash_allocations, :allocation_suggestions)
                      .paginate(page: params[:page], per_page: PAR_PAGE)

      # Les suggestions se recalculent à l'ouverture de l'écran : c'est le seul
      # moment où elles servent, et ça évite un job de fond que l'application
      # n'a pas les moyens de garantir. Sur les lignes AFFICHÉES seulement — les
      # recalculer toutes coûtait 38 secondes à chaque page.
      Finance::SuggestAllocations.new(cash_entries: @entries, whodunnit: current_user&.email).run!

      # Le rapprochement de séjour se calcule à l'affichage : il dépend de
      # l'état des soldes, qui bouge à chaque paiement.
      # Les séjours ouverts et leurs soldes, calculés UNE fois pour la page.
      stays, soldes = Finance::MatchStay.prechargement(@entries)

      @stay_matches = @entries.each_with_object({}) do |entry, hash|
        next if entry.cash_allocations.any?

        correspondance = Finance::MatchStay.new(cash_entry: entry, open_stays: stays, soldes: soldes).run!
        next if correspondance.nil?

        lignes = begin
          Finance::VentilateStay.new(stay: correspondance.stay, amount_cents: entry.amount_cents).run!
        rescue Finance::VentilateStay::EmptyQuote, Finance::VentilateStay::MissingMapping
          nil
        end
        next if lignes.blank?

        hash[entry.id] = { match: correspondance, lines: lignes }
      end
      # Les virements aux membres (epic #246, phase 2) : une ligne sortante peut
      # solder le compte créditeur d'un cuisinier. Les soldes se calculent UNE
      # fois pour la page — les recalculer ligne à ligne est ce qui avait fait
      # tomber cet écran à l'issue #202.
      @payout_matches = Finance::MatchMemberPayouts.new.for_entries(@entries)
      # Les factures d'achat à payer (epic #240, phase 4) : une ligne sortante
      # dont le montant ou l'IBAN correspond à une facture `to_pay`. Les
      # factures sont chargées UNE fois pour la page, comme les soldes.
      @invoice_matches = Finance::MatchPurchaseInvoices.new.for_entries(@entries)
      # Les notes de frais et de mission à payer (epic #241, phase 3) : même
      # geste que la facture, sur une autre dette. Les notes `processing` sont
      # chargées UNE fois pour la page, comme les factures.
      @expense_report_matches = Finance::MatchExpenseReports.new.for_entries(@entries)
      # Les versements Stripe (epic #250, phase 2) : une ligne bancaire ENTRANTE
      # dont le montant et la date correspondent à un versement pas encore
      # rapproché. Les versements sont chargés UNE fois pour la page.
      @stripe_matches = Finance::MatchStripePayouts.new.for_entries(@entries)
      # Les règlements des habitants (issue #349) : le miroir des virements
      # ci-dessus. Une ligne ENTRANTE peut éteindre la dette d'un ménage ou
      # d'une personne. Les soldes débiteurs sont chargés UNE fois pour la page.
      @settlement_matches = Finance::MatchMemberSettlements.new.for_entries(@entries)

      @general_accounts = GeneralAccount.actives.ordered
      @teams = Team.ordered
      @entities = LegalEntity.actives.ordered
      @events = recent_events
    end

    def show
      breadcrumb @entry.label, finance_cash_entry_path(@entry), match: :exact

      @allocations = @entry.cash_allocations.includes(:general_account, :team, :legal_entity, :document).ordered
      @allocation = CashAllocation.new(amount_cents: @entry.remaining_cents)
      @general_accounts = GeneralAccount.actives.ordered
      @teams = Team.ordered
      @entities = LegalEntity.actives.ordered
      @events = recent_events
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

    # Le virement qui solde le compte d'un membre (epic #246, phase 2). Un geste,
    # pas deux : l'écriture sur son compte et l'affectation de la ligne bancaire
    # tombent ensemble ou pas du tout.
    def payout
      compte = MemberAccount.find(params[:member_account_id])
      # Sans montant explicite, on solde : c'est le geste courant. Le paramètre
      # existe pour un virement partiel, et c'est lui qui se fait refuser s'il
      # dépasse ce que le compte attend.
      montant = params[:amount].presence && (params[:amount].to_s.tr(",", ".").to_f * 100).round

      Finance::RecordMemberPayout.new(
        member_account: compte, cash_entry: @entry, amount_cents: montant,
        whodunnit: current_user&.email
      ).run!

      redirect_to finance_unallocated_cash_entries_path,
                  notice: "Virement à #{compte.name} enregistré — son compte est soldé."
    rescue Finance::RecordMemberPayout::NotCreditor, Finance::RecordMemberPayout::TooMuch,
           Finance::RecordMemberPayout::MissingAccount, Finance::RecordMemberPayout::WrongDirection,
           ActiveRecord::RecordInvalid => e
      redirect_to finance_cash_entry_path(@entry), alert: e.message
    end

    # Le règlement d'un habitant encaissé depuis une ligne ENTRANTE (issue
    # #349) : le miroir de `payout`. Un geste, pas deux — le règlement sur son
    # compte courant et l'affectation de la ligne bancaire tombent ensemble ou
    # pas du tout.
    def settle
      compte = MemberAccount.find(params[:member_account_id])
      # Sans montant explicite, on impute le minimum entre la ligne et la dette :
      # c'est le geste courant. Le paramètre existe pour un règlement partiel.
      montant = params[:amount].presence && (params[:amount].to_s.tr(",", ".").to_f * 100).round

      Finance::RecordMemberSettlement.new(
        member_account: compte, cash_entry: @entry, amount_cents: montant,
        flow: params[:flow], whodunnit: current_user&.email
      ).run!

      redirect_to finance_unallocated_cash_entries_path,
                  notice: "Règlement de #{compte.name} enregistré sur le poste " \
                          "#{AccountEntry::FLOW_LABELS.fetch(params[:flow], 'Divers')}."
    # La contrainte d'unicité sur `account_entries.idempotency_key` a tranché :
    # ce virement est déjà imputé sur ce compte, et la transaction n'a rien
    # écrit. Ce n'est pas une erreur — sur un écran qui aligne des dizaines de
    # propositions, le double clic et le retour-arrière sont la règle, pas
    # l'exception. Le message brut de Postgres ne se montre pas à quelqu'un qui
    # encode, d'où ce `rescue` distinct des refus métier.
    rescue ActiveRecord::RecordNotUnique
      redirect_to finance_unallocated_cash_entries_path,
                  alert: "Ce virement est déjà imputé sur #{compte.name} — rien n'a été enregistré une seconde fois."
    rescue Finance::RecordMemberSettlement::NotDebtor, Finance::RecordMemberSettlement::TooMuch,
           Finance::RecordMemberSettlement::MissingAccount, Finance::RecordMemberSettlement::WrongDirection,
           Accounting::PostCashEntry::NotFullyAllocated,
           ActiveRecord::RecordInvalid => e
      redirect_to finance_cash_entry_path(@entry), alert: e.message
    end

    # Payer une facture d'achat depuis une ligne sortante (epic #240, phase 4).
    # La proposition n'a rien écrit : c'est CE clic qui crée l'allocation.
    def pay_invoice
      facture = PurchaseInvoice.find(params[:purchase_invoice_id])
      montant = params[:amount].presence && (params[:amount].to_s.tr(",", ".").to_f * 100).round

      Finance::RecordInvoicePayment.new(
        purchase_invoice: facture, cash_entry: @entry, amount_cents: montant,
        whodunnit: current_user&.email
      ).run!

      redirect_to finance_unallocated_cash_entries_path,
                  notice: "#{facture.payable_label} rapprochée de cette ligne."
    rescue Finance::RecordInvoicePayment::NotPayable, Finance::RecordInvoicePayment::TooMuch,
           Finance::RecordInvoicePayment::WrongDirection, Finance::RecordInvoicePayment::MissingAccount,
           Accounting::PostCashEntry::NotFullyAllocated,
           ActiveRecord::RecordInvalid => e
      redirect_to finance_cash_entry_path(@entry), alert: e.message
    end

    # Rapprocher une ligne sortante d'une note de frais ou de mission (epic #241,
    # phase 3). La proposition n'a rien écrit : c'est CE clic qui affecte.
    def pay_expense_report
      note = ExpenseReport.find(params[:expense_report_id])
      montant = params[:amount].presence && (params[:amount].to_s.tr(",", ".").to_f * 100).round

      Finance::RecordExpenseReportPayment.new(
        expense_report: note, cash_entry: @entry, amount_cents: montant,
        whodunnit: current_user&.email
      ).run!

      redirect_to finance_unallocated_cash_entries_path,
                  notice: "#{note.payable_label} rapprochée de cette ligne."
    rescue Finance::RecordExpenseReportPayment::NotPayable,
           Finance::RecordExpenseReportPayment::TooMuch,
           Finance::RecordExpenseReportPayment::WrongDirection,
           Finance::RecordExpenseReportPayment::MissingAccount,
           Accounting::PostCashEntry::NotFullyAllocated,
           ActiveRecord::RecordInvalid => e
      redirect_to finance_cash_entry_path(@entry), alert: e.message
    end

    # Rapprocher une ligne bancaire de son versement Stripe (epic #250, phase 2).
    # La proposition n'a rien écrit : c'est CE clic qui affecte.
    def reconcile_payout
      versement = StripePayout.find(params[:stripe_payout_id])

      Finance::RecordStripePayoutReconciliation.new(
        stripe_payout: versement, cash_entry: @entry, whodunnit: current_user&.email
      ).run!

      redirect_to finance_unallocated_cash_entries_path,
                  notice: "Versement Stripe #{versement.account_label} rapproché de cette ligne."
    rescue Finance::RecordStripePayoutReconciliation::WrongDirection,
           Finance::RecordStripePayoutReconciliation::AlreadyReconciled,
           Finance::RecordStripePayoutReconciliation::AmountMismatch,
           Finance::RecordStripePayoutReconciliation::PerPayoutUnsupported,
           Finance::VentilateStripePayout::Unbalanced,
           Finance::VentilateStripePayout::MissingMapping,
           Accounting::PostCashEntry::NotFullyAllocated,
           ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid => e
      redirect_to finance_cash_entry_path(@entry), alert: e.message
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

    def entry_params
      permitted = params.require(:cash_entry).permit(:cash_account_id, :entry_date, :value_date, :label,
                                                     :counterparty_name, :counterparty_iban, :communication,
                                                     :external_ref, :statement_ref, :amount)
      amount = permitted.delete(:amount)
      permitted[:amount_cents] = Monetize.parse(amount.to_s).cents if amount.present?
      permitted
    end

    # Les événements proposables au rattachement d'une recette (epic #245,
    # phase 2) : dix-huit mois en arrière et l'avenir. Au-delà, la liste devient
    # une roue interminable pour retrouver un stage de 2023 que plus personne
    # n'encaisse.
    def recent_events
      Event.where("starts_at >= ?", 18.months.ago).order(starts_at: :desc)
    end

    def parsed_date(raw)
      raw.present? ? Date.parse(raw) : nil
    rescue Date::Error
      nil
    end
  end
end
