module Finance
  # Une transaction du solde Stripe devient une ou deux lignes de trésorerie
  # (epic #250, phase 1, décision 5).
  #
  # C'est le cœur du mode `ledger`. Le solde Stripe est un vrai compte de
  # trésorerie : un encaissement de 10 € avec 29 centimes de commission n'y
  # entre pas comme une ligne nette de 9,71 €, mais comme DEUX lignes — la
  # recette brute, et la commission en négatif. Sans ça, le coût d'encaissement
  # disparaît dans la recette et on ne sait plus ce que coûte le fait d'être payé
  # par carte.
  #
  # Deux lignes plutôt qu'une allocation à cheval, parce qu'une allocation garde
  # le signe de sa ligne (validation de `CashAllocation`) : une recette positive
  # et une charge négative sur une même ligne sont refusées, et elles ont raison
  # de l'être.
  #
  # Ce que le service n'invente jamais : l'affectation d'une recette. Elle vient
  # d'une `StripeCategoryMapping` décidée par un humain. Sans correspondance, la
  # ligne reste `pending` sur « À affecter » — visible, jamais rangée d'office.
  class RecordStripeTransaction < ServiceBase
    class MissingAccount < StandardError; end
    class MissingCashAccount < StandardError; end

    FEE_ACCOUNT_CODE = "618000".freeze
    TRANSFER_ACCOUNT_CODE = GeneralAccount::INTERNAL_TRANSFER_CODE

    # Ce qu'une ligne est, avant d'exister en base.
    Draft = Struct.new(:suffix, :amount_cents, :label, :general_account_code, :category_mapped,
                       :document, keyword_init: true)

    def initialize(transaction:, whodunnit: nil)
      @transaction = transaction
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { stripe_balance_transaction: @transaction.id }) { record }
    end

    def run! = record

    # Ce que la transaction PRODUIRAIT, sans rien écrire. C'est ce dont vit le
    # dry-run du rake : annoncer les lignes et les catégories manquantes avant
    # que quoi que ce soit ne touche le journal.
    def preview = drafts

    private

    def record
      account = @transaction.cash_account
      raise MissingCashAccount, "La transaction #{@transaction.stripe_id} n'a pas de compte Stripe." if account.nil?

      created = []

      PaperTrail.request(whodunnit: @whodunnit || "stripe") do
        drafts.each do |draft|
          next if draft.amount_cents.zero?

          reference = "stripe:#{@transaction.stripe_id}:#{draft.suffix}"
          next if already_recorded?(account, reference)

          ApplicationRecord.transaction do
            entry = CashEntry.create!(
              cash_account: account,
              source: @transaction,
              entry_date: entry_date,
              value_date: @transaction.available_on,
              amount_cents: draft.amount_cents,
              label: draft.label,
              external_ref: reference
            )

            allocate(entry, draft)
            Accounting::PostCashEntry.new(cash_entry: entry, whodunnit: @whodunnit).run! if entry.reload.fully_allocated?
            created << entry
          end
        end
      end

      created
    end

    # Une ligne déjà écrite ne se réécrit pas — soft-deletées comprises : une
    # ligne retirée à la main ne doit pas repousser à la synchronisation
    # suivante.
    def already_recorded?(account, reference)
      CashEntry.with_deleted { CashEntry.exists?(cash_account_id: account.id, external_ref: reference) }
    end

    def drafts
      case @transaction.kind
      when "charge", "payment", "adjustment" then revenue_drafts
      when "refund", "payment_refund" then revenue_drafts
      when "stripe_fee" then [fee_only_draft]
      when "payout" then [payout_draft]
      else [unclassified_draft]
      end
    end

    # Recette brute + commission. Vaut aussi pour un remboursement : le brut y
    # est négatif et la commission rendue l'est aussi, les signes s'occupent du
    # reste.
    def revenue_drafts
      [
        Draft.new(suffix: "gross", amount_cents: @transaction.gross_cents,
                  label: revenue_label, category_mapped: true),
        Draft.new(suffix: "fee", amount_cents: -@transaction.fee_cents,
                  label: "Commission Stripe — #{revenue_label}",
                  general_account_code: FEE_ACCOUNT_CODE)
      ]
    end

    # Les frais facturés à part — l'abonnement mensuel, une contestation. Ils ne
    # portent pas de `fee` : leur net EST le coût, en négatif.
    def fee_only_draft
      Draft.new(suffix: "net", amount_cents: @transaction.net_cents,
                label: @transaction.description.presence || "Frais Stripe",
                general_account_code: FEE_ACCOUNT_CODE)
    end

    # Le versement vers la banque : de l'argent qui QUITTE le solde Stripe, donc
    # une ligne négative, affectée sur le compte de virements internes. La ligne
    # bancaire correspondante viendra s'y affecter aussi, en positif — et
    # `rake accounting:verify_internal_transfers` vérifie que la somme vaut zéro.
    def payout_draft
      payout = @transaction.stripe_payout
      montant = payout&.amount_cents&.abs || @transaction.net_cents.abs

      Draft.new(suffix: "net", amount_cents: -montant,
                label: payout ? "Versement Stripe #{payout.stripe_id}" : "Versement Stripe",
                general_account_code: TRANSFER_ACCOUNT_CODE, document: payout)
    end

    # `transfer` et `other` : on ne sait pas. La ligne existe, elle attend sur
    # « À affecter », et quelqu'un décidera. C'est exactement ce qu'on veut —
    # pas un compte fourre-tout qui absorbe ce qu'on n'a pas compris.
    def unclassified_draft
      Draft.new(suffix: "net", amount_cents: @transaction.net_cents,
                label: @transaction.description.presence || "Mouvement Stripe #{@transaction.kind}")
    end

    def allocate(entry, draft)
      attributes = allocation_attributes(draft)
      return if attributes.blank?

      entry.cash_allocations.create!(
        attributes.merge(amount_cents: entry.amount_cents, label: entry.label, document: draft.document)
      )
    end

    def allocation_attributes(draft)
      if draft.general_account_code.present?
        { general_account: fetch_account(draft.general_account_code), legal_entity: entity }
      elsif draft.category_mapped
        mapping = StripeCategoryMapping.for(@transaction.account_key, @transaction.mapping_category)
        mapping&.allocation_attributes(fallback_entity: entity)
      end
    end

    def revenue_label
      [@transaction.category.presence, @transaction.description.presence]
        .compact.first || "Encaissement Stripe"
    end

    def entry_date = (@transaction.occurred_at || Time.current).to_date

    def entity = @transaction.cash_account.legal_entity

    def fetch_account(code)
      GeneralAccount.find_by(code: code) ||
        raise(MissingAccount, "Le compte #{code} n'existe pas — lance `rake accounting:seed_reference`.")
    end
  end
end
