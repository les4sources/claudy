module Finance
  # Le journal de trésorerie (issue #179).
  #
  # L'écran « À affecter » est le cœur du dispositif : son compteur doit pouvoir
  # tomber à zéro à la fin d'un mois. C'est le seul indicateur qui dit, en un
  # coup d'œil, si la comptabilité est à jour — et il remplace des heures de
  # rapprochement annuel par un geste mensuel.
  class CashEntriesController < Finance::AccountingBaseController
    include Finance::UnallocatedQueue

    before_action :get_entry,
                  only: [:show, :edit, :update, :post_entry, :unpost, :exclude, :ventilate, :payout,
                         :pay_invoice, :pay_expense_report, :reconcile_payout, :collect_sales_invoice,
                         :settle, :suggestion, :detail]
    breadcrumb "Trésorerie", :finance_cash_entries_path, match: :exact

    # Le journal se lit, il ne se travaille pas ligne à ligne. Ses pages étaient
    # deux fois plus longues que celles de la file « À affecter » ; la file est
    # passée à la même longueur quand elle a cessé de se recharger à chaque geste.
    JOURNAL_PAR_PAGE = 50

    def index
      @accounts = CashAccount.ordered
      @account = CashAccount.find_by(id: params[:cash_account_id])
      @status = params[:status].presence
      @from = parsed_date(params[:from]) || Date.current.beginning_of_year
      @to = parsed_date(params[:to]) || Date.current.end_of_year

      @query = params[:q].to_s.strip

      scope = CashEntry.ordered.in_period(@from, @to).includes(:cash_account, :cash_allocations)
      scope = scope.where(cash_account_id: @account.id) if @account
      scope = scope.where(status: @status) if @status
      scope = scope.matching(@query) if @query.present?

      # Le journal se PAGINE (Michael, 2026-09-20). Il rendait l'année entière
      # d'un coup : 2 445 lignes et 2,7 Mo de HTML sur 2026, et ça grossit de
      # mois en mois. Le compteur « à affecter » reste global — c'est le
      # chiffre qui doit tomber à zéro, pas celui de la page qu'on regarde.
      @total = scope.count
      @entries = scope.paginate(page: params[:page], per_page: JOURNAL_PAR_PAGE)
      @comment_counts = comment_counts(@entries)

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
    # Tout le travail est donc borné à la PAGE affichée (`charger_pistes`). Le
    # compteur, lui, reste global : savoir combien de lignes attendent est
    # l'information la plus utile de cet écran, et elle ne coûte qu'un COUNT.
    def unallocated
      @pending_total = CashEntry.pending.count

      # La file se FILTRE (epic #288, phase 4) : recherche, compte ou famille
      # de comptes, période, sens, montant. L'arrêté du mois y renvoie filtré
      # sur Stripe quand une recette attend sa correspondance (epic #250).
      # Sans filtre, on retombe sur la file entière. Le calcul des pistes reste
      # borné à la page affichée : filtrer ne le fait jamais porter sur tout.
      @filter = Finance::QueueFilter.new(queue_filter_params)
      @accounts = CashAccount.ordered
      scope = @filter.scope
      @filtered_total = scope.count

      @entries = scope.includes(:cash_account, :cash_allocations, :allocation_suggestions)
                      .paginate(page: params[:page], per_page: PAR_PAGE)
      charger_pistes(@entries)
    end

    # Le cadre de la proposition d'une ligne de la file « À affecter ». Jev
    # répond en environ 300 ms : demandé ligne par ligne, à la volée, il ne
    # retient jamais l'écran, et une page de 50 lignes se complète en quelques
    # secondes. La ligne n'est demandée qu'une fois (`jev_checked_at`).
    def suggestion
      Finance::SuggestAllocations.new(cash_entries: [@entry], whodunnit: current_user&.email,
                                      jev: Jev::Client.new).run!
      charger_artisans
      render partial: "suggestion", locals: { entry: @entry, suggestion: @entry.allocation_suggestions.pending.ordered.first }
    end

    def show
      breadcrumb @entry.label, finance_cash_entry_path(@entry), match: :exact

      @allocations = @entry.cash_allocations.includes(:general_account, :team, :legal_entity, :document).ordered
      @allocation = CashAllocation.new(amount_cents: @entry.remaining_cents)
      @general_accounts = GeneralAccount.actives.ordered
      @teams = Team.ordered
      @entities = LegalEntity.actives.ordered
      @events = recent_events
      charger_artisans
    end

    # Le détail d'une ligne, ouvert en modale depuis la file « À affecter »
    # (epic #288, phase 5). Quand les quatre colonnes ne suffisent pas, c'est
    # ici qu'on lit la date de valeur, le code opération, l'IBAN et la
    # référence du relevé — sans quitter sa page de la file. La modale montre,
    # elle ne classe pas : on affecte dans la file. La page pleine (`show`)
    # reste l'URL qu'on partage.
    def detail
      @allocations = @entry.cash_allocations.includes(:general_account, :team, :legal_entity).ordered
      # Même raison que `Finance::AccountsController#poste` : le layout de
      # l'application porte déjà un cadre « modal » vide, que Turbo prendrait.
      render layout: "modal"
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

      apres_affectation(@entry, finance_unallocated_cash_entries_path,
                        notice: "Virement à #{compte.name} enregistré — son compte est soldé.")
    rescue Finance::RecordMemberPayout::NotCreditor, Finance::RecordMemberPayout::TooMuch,
           Finance::RecordMemberPayout::MissingAccount, Finance::RecordMemberPayout::WrongDirection,
           ActiveRecord::RecordInvalid => e
      apres_affectation(@entry, finance_cash_entry_path(@entry), alert: e.message)
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

      apres_affectation(@entry, finance_unallocated_cash_entries_path,
                        notice: "Règlement de #{compte.name} enregistré sur le poste " \
                                "#{AccountEntry::FLOW_LABELS.fetch(params[:flow], 'Divers')}.")
    # La contrainte d'unicité sur `account_entries.idempotency_key` a tranché :
    # ce virement est déjà imputé sur ce compte, et la transaction n'a rien
    # écrit. Ce n'est pas une erreur — sur un écran qui aligne des dizaines de
    # propositions, le double clic et le retour-arrière sont la règle, pas
    # l'exception. Le message brut de Postgres ne se montre pas à quelqu'un qui
    # encode, d'où ce `rescue` distinct des refus métier.
    rescue ActiveRecord::RecordNotUnique
      apres_affectation(@entry, finance_unallocated_cash_entries_path,
                        alert: "Ce virement est déjà imputé sur #{compte.name} — rien n'a été enregistré une seconde fois.")
    rescue Finance::RecordMemberSettlement::NotDebtor, Finance::RecordMemberSettlement::TooMuch,
           Finance::RecordMemberSettlement::MissingAccount, Finance::RecordMemberSettlement::WrongDirection,
           Accounting::PostCashEntry::NotFullyAllocated,
           ActiveRecord::RecordInvalid => e
      apres_affectation(@entry, finance_cash_entry_path(@entry), alert: e.message)
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

      apres_affectation(@entry, finance_unallocated_cash_entries_path,
                        notice: "#{facture.payable_label} rapprochée de cette ligne.")
    rescue Finance::RecordInvoicePayment::NotPayable, Finance::RecordInvoicePayment::TooMuch,
           Finance::RecordInvoicePayment::WrongDirection, Finance::RecordInvoicePayment::MissingAccount,
           Accounting::PostCashEntry::NotFullyAllocated,
           ActiveRecord::RecordInvalid => e
      apres_affectation(@entry, finance_cash_entry_path(@entry), alert: e.message)
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

      apres_affectation(@entry, finance_unallocated_cash_entries_path,
                        notice: "#{note.payable_label} rapprochée de cette ligne.")
    rescue Finance::RecordExpenseReportPayment::NotPayable,
           Finance::RecordExpenseReportPayment::TooMuch,
           Finance::RecordExpenseReportPayment::WrongDirection,
           Finance::RecordExpenseReportPayment::MissingAccount,
           Accounting::PostCashEntry::NotFullyAllocated,
           ActiveRecord::RecordInvalid => e
      apres_affectation(@entry, finance_cash_entry_path(@entry), alert: e.message)
    end

    # Rapprocher une ligne bancaire de son versement Stripe (epic #250, phase 2).
    # La proposition n'a rien écrit : c'est CE clic qui affecte.
    def reconcile_payout
      versement = StripePayout.find(params[:stripe_payout_id])

      Finance::RecordStripePayoutReconciliation.new(
        stripe_payout: versement, cash_entry: @entry, whodunnit: current_user&.email
      ).run!

      apres_affectation(@entry, finance_unallocated_cash_entries_path,
                        notice: "Versement Stripe #{versement.account_label} rapproché de cette ligne.")
    rescue Finance::RecordStripePayoutReconciliation::WrongDirection,
           Finance::RecordStripePayoutReconciliation::AlreadyReconciled,
           Finance::RecordStripePayoutReconciliation::AmountMismatch,
           Finance::RecordStripePayoutReconciliation::PerPayoutUnsupported,
           Finance::VentilateStripePayout::Unbalanced,
           Finance::VentilateStripePayout::MissingMapping,
           Accounting::PostCashEntry::NotFullyAllocated,
           ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid => e
      apres_affectation(@entry, finance_cash_entry_path(@entry), alert: e.message)
    end

    # Encaisser une facture de vente depuis une ligne entrante (epic #240,
    # phase 6). La ventilation en recettes est celle d'aujourd'hui — seul le
    # `document` des allocations change, et c'est lui qui fait passer la facture
    # en « payée ». AUCUNE écriture de vente n'est générée (décision 8).
    def collect_sales_invoice
      facture = SalesInvoice.find(params[:sales_invoice_id])
      lignes = Finance::RecordSalesInvoicePayment.new(
        sales_invoice: facture, cash_entry: @entry, whodunnit: current_user&.email
      ).run!

      apres_affectation(@entry, finance_unallocated_cash_entries_path,
                        notice: "Facture #{facture.number} encaissée — #{lignes.size} ligne(s) de recette, " \
                                "l'IBAN est mémorisé pour ce client.")
    rescue Finance::RecordSalesInvoicePayment::WrongDirection,
           Finance::RecordSalesInvoicePayment::AlreadyPaid,
           Finance::RecordSalesInvoicePayment::NoVentilableSource,
           Finance::VentilateStay::EmptyQuote, Finance::VentilateStay::MissingMapping,
           Accounting::PostCashEntry::NotFullyAllocated,
           Accounting::PostDocument::MissingFiscalYear,
           ActiveRecord::RecordInvalid => e
      apres_affectation(@entry, finance_cash_entry_path(@entry), alert: e.message)
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

      apres_affectation(@entry, finance_cash_entry_path(@entry),
                        notice: "Séjour ##{stay.id} ventilé en #{lignes.size} ligne(s) — l'IBAN est mémorisé pour ce client.")
    rescue Finance::VentilateStay::EmptyQuote, Finance::VentilateStay::MissingMapping,
           Accounting::PostDocument::MissingFiscalYear => e
      apres_affectation(@entry, finance_cash_entry_path(@entry), alert: e.message)
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

    def queue_filter_params
      params.slice(*Finance::QueueFilter::KEYS).permit(*Finance::QueueFilter::KEYS)
    end

    def parsed_date(raw)
      raw.present? ? Date.parse(raw) : nil
    rescue Date::Error
      nil
    end
  end
end
