module Finance
  # Porte les écritures d'une session de batch cooking (epic #246).
  #
  # UNE ligne de service = UNE charge sur le compte du ménage (+ portions × 5 €).
  # UN cuisinier = UN crédit sur SON compte personnel (− portions × 3,50 €) —
  # pas sur celui de son ménage : un enfant qui cuisine gagne cet argent, et
  # c'est le sien. Michael a refusé la compensation sur le décompte du ménage.
  #
  # Les deux montants unitaires sont lus dans `Rate` À LA DATE DE LA SESSION et
  # FIGÉS sur chaque écriture (`unit_price_cents`), comme les fiches papier.
  # Un barème corrigé aujourd'hui ne réécrit donc pas une session de juin : la
  # lecture datée ne voit que la version qui couvrait ce jour-là.
  #
  # Le service est REJOUABLE. Chaque écriture porte une clé d'idempotence
  # (`batchcooking:<session>:serving:<compte>` et
  # `batchcooking:<session>:cook:<humain>`) : rejouer met à jour ce qui a
  # changé, supprime ce qui a disparu de la session, et ne crée jamais un
  # second jeu. C'est ce qui permet de corriger une saisie en revenant dessus.
  #
  # UNE ÉCRITURE VERROUILLÉE ARRÊTE TOUT. Rattachée à un décompte émis, elle ne
  # peut plus bouger sans faire mentir un document déjà envoyé : le service
  # refuse la modification, et l'écran propose la contre-écriture.
  class RecordBatchCooking < ServiceBase
    SERVING_RATE_KEY = "meal.batchcooking.per_person".freeze
    COOK_RATE_KEY = "meal.batchcooking.cook_volunteering".freeze

    KEY_PREFIX = "batchcooking".freeze

    Report = Struct.new(:created, :updated, :deleted, :unchanged, keyword_init: true) do
      def touched = created + updated + deleted

      def summary
        "#{created} écriture(s) créée(s), #{updated} mise(s) à jour, #{deleted} supprimée(s)"
      end
    end

    def initialize(session:, whodunnit: nil)
      @session = session
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { batch_cooking_session: @session.id }) { record }
    end

    def run!
      record
    end

    private

    def record
      wanted = wanted_entries

      PaperTrail.request(whodunnit: @whodunnit || "batch_cooking") do
        ApplicationRecord.transaction do
          report = Report.new(created: 0, updated: 0, deleted: 0, unchanged: 0)
          existing = existing_entries

          refuse_locked_changes(wanted, existing)
          drop_obsolete(wanted, existing, report)
          wanted.each { |key, attrs| apply(key, attrs, existing[key], report) }
          report
        end
      end
    end

    # L'état VOULU, calculé depuis les lignes de la session. Rien n'est écrit
    # ici : ce qui est refusé l'est avant qu'une seule écriture ne bouge.
    def wanted_entries
      serving_price = price_for(SERVING_RATE_KEY)
      cook_price = price_for(COOK_RATE_KEY)
      wanted = {}

      @session.servings.includes(:member_account).each do |serving|
        account = serving_account(serving)
        wanted[serving_key(account.id)] = {
          member_account_id: account.id,
          amount_cents: serving.portions * serving_price,
          quantity: serving.portions,
          unit_price_cents: serving_price,
          kind: "batchcooking",
          label: label_for(serving.portions)
        }
      end

      @session.cooks.each do |cook|
        next if cook.portions.to_i.zero?

        account = cook_account(cook)
        wanted[cook_key(cook.human_id)] = {
          member_account_id: account.id,
          # Négatif : le crédit est EN FAVEUR du cuisinier. Arrondi au cent —
          # une part de 2,333 portions ne tombe pas juste, et c'est le montant
          # qui doit être exact, pas la multiplication.
          amount_cents: -(cook.portions * cook_price).round,
          quantity: cook.portions,
          unit_price_cents: cook_price,
          kind: "cook_fee",
          label: label_for(cook.portions)
        }
      end

      wanted
    end

    # Toutes les écritures déjà posées par CETTE session, soft-deletées
    # comprises : la clé d'idempotence est unique en base, une écriture
    # supprimée en douceur bloquerait la recréation sans qu'on la voie.
    def existing_entries
      AccountEntry.unscoped
                  .where("idempotency_key LIKE ?", "#{KEY_PREFIX}:#{@session.id}:%")
                  .index_by(&:idempotency_key)
    end

    # Le verrou se vérifie AVANT toute écriture : une session à moitié
    # régénérée serait pire que refusée.
    def refuse_locked_changes(wanted, existing)
      bloquantes = existing.filter_map do |key, entry|
        next unless entry.locked?

        attrs = wanted[key]
        next if attrs && unchanged?(entry, frozen(attrs, entry))

        entry
      end
      return if bloquantes.empty?

      raise ServiceError,
            "#{bloquantes.size} écriture(s) de cette session sont rattachées à un décompte émis : " \
            "elles ne peuvent plus être modifiées. Passe par une contre-écriture."
    end

    # Une ligne retirée de la session emporte son écriture. Les verrouillées ont
    # déjà fait échouer le service plus haut.
    def drop_obsolete(wanted, existing, report)
      existing.each do |key, entry|
        next if wanted.key?(key)

        entry.destroy!
        report.deleted += 1
      end
    end

    def apply(key, attrs, entry, report)
      if entry.nil?
        AccountEntry.create!(attrs.merge(
                               entry_date: @session.cooked_on,
                               posted_at: Time.current,
                               flow: "meal",
                               source: "batch_cooking",
                               idempotency_key: key
                             ))
        return report.created += 1
      end

      voulu = frozen(attrs, entry)
      return report.unchanged += 1 if unchanged?(entry, voulu)

      entry.update!(voulu.merge(entry_date: @session.cooked_on))
      report.updated += 1
    end

    # Le prix d'une écriture déjà posée ne bouge plus : c'est la promesse de la
    # décision 3, et c'est ce qui fait qu'une session de juin corrigée en
    # septembre reste facturée au tarif de juin. Seules les portions font donc
    # bouger le montant, recalculé sur le prix FIGÉ — sinon la ligne afficherait
    # « 3 × 5,00 € = 18,00 € », un montant que sa propre multiplication dément.
    def frozen(attrs, entry)
      price = entry.unit_price_cents.presence || attrs[:unit_price_cents]
      sign = attrs[:amount_cents].negative? ? -1 : 1

      attrs.merge(unit_price_cents: price,
                  amount_cents: sign * (attrs[:quantity] * price).round)
    end

    def unchanged?(entry, attrs)
      entry.member_account_id == attrs[:member_account_id] &&
        entry.amount_cents == attrs[:amount_cents] &&
        entry.quantity == attrs[:quantity] &&
        entry.label == attrs[:label] &&
        entry.entry_date == @session.cooked_on
    end

    def serving_account(serving)
      account = MemberAccount.find_by(id: serving.member_account_id)
      unless account
        raise ServiceError, "Un ménage servi n'a plus de compte : corrige la session avant d'enregistrer."
      end
      unless account.active?
        raise ServiceError,
              "Le compte « #{account.name} » (#{account.code}) est désactivé : " \
              "réactive-le ou retire-le de la session."
      end

      account
    end

    # Le cuisinier est payé sur SON compte, créé au passage s'il n'existe pas.
    # `Human` porte un `default_scope` sur les actifs : on le lit sans scope,
    # sinon une personne partie ferait échouer une session qu'on rejoue.
    def cook_account(cook)
      human = Human.unscoped.find_by(id: cook.human_id)
      unless human
        raise ServiceError,
              "Un cuisinier de cette session n'existe plus comme personne : " \
              "crée la personne, puis reprends la session."
      end

      MemberAccount.for_human!(human)
    end

    def price_for(key)
      cents = Pricing::Rates.cents(key, on: @session.cooked_on)
      return cents if cents

      raise ServiceError,
            "Aucun tarif « #{key} » ne couvre le #{I18n.l(@session.cooked_on, format: :ddmmyyyy)} : " \
            "ajoute une version du barème dans Paramètres > Tarifs."
    end

    # « Batch cooking du 12/09 — 5 portions », plus le nom de la session quand
    # elle en porte un : sur un décompte, « Chili » dit plus que la date.
    def label_for(portions)
      base = "Batch cooking du #{@session.cooked_on.strftime('%d/%m')} — #{portions_label(portions)}"
      @session.label.present? ? "#{base} · #{@session.label}" : base
    end

    # « 5 portions », « 2,5 portions », « 1 portion ». Les zéros de queue d'un
    # décimal (2.500) n'ont rien à faire sur un décompte.
    def portions_label(portions)
      value = BigDecimal(portions.to_s)
      texte = value.frac.zero? ? value.to_i.to_s : value.to_s("F").sub(/0+\z/, "").tr(".", ",")

      "#{texte} #{value <= 1 ? 'portion' : 'portions'}"
    end

    def serving_key(account_id) = "#{KEY_PREFIX}:#{@session.id}:serving:#{account_id}"

    def cook_key(human_id) = "#{KEY_PREFIX}:#{@session.id}:cook:#{human_id}"
  end
end
