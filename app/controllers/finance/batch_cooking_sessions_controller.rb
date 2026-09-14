module Finance
  # Finances > Batch cooking (epic #246).
  #
  # L'écran de saisie de Stéphanie : les portions par famille, qui a cuisiné, et
  # ce que ça fait — en une minute, depuis la cuisine, sur un téléphone.
  #
  # Les cuisiniers sont choisis parmi les MEMBRES DE MÉNAGE (adultes et
  # enfants), pas parmi les `Human` : c'est la liste que Stéphanie a en tête. Un
  # membre sans `human_id` ne peut pas être payé — il n'a pas d'identité à qui
  # ouvrir un compte — donc l'écran refuse et propose de créer la personne,
  # nom pré-rempli.
  class BatchCookingSessionsController < Finance::BaseController
    before_action :get_session, only: %i[edit update destroy]

    breadcrumb "Batch cooking", :finance_batch_cooking_sessions_path, match: :exact

    def index
      @sessions = BatchCookingSession.recent_first
                                     .includes(servings: :member_account, cooks: [])
                                     .limit(60)
                                     .to_a
      @entries = entries_by_session(@sessions)
      # Les cuisiniers à payer (epic #246, phase 2). La file « À payer » de
      # l'epic #240 (phase 4) n'existe pas encore : en attendant, la dette vit
      # ICI, là où les sessions se saisissent. Un cuisinier qu'on oublie de
      # payer est le meilleur moyen de ne plus en avoir.
      @payables = Finance::MemberPayables.new
    end

    def new
      @session = BatchCookingSession.new(cooked_on: Date.current)
      prepare_form
    end

    def create
      @session = BatchCookingSession.new(session_params.merge(created_by: current_user))
      save_and_record { @session.save! }
    end

    def edit
      prepare_form
    end

    def update
      save_and_record { @session.update!(session_params) }
    end

    def destroy
      # Les écritures partent AVANT la session : après, plus rien ne sait
      # lesquelles étaient les siennes, et le décompte d'un ménage garderait
      # une charge dont la session a disparu.
      supprimer_ecritures
      @session.soft_delete!(validate: false)
      redirect_to finance_batch_cooking_sessions_path, notice: "Session supprimée."
    rescue AccountEntry::Locked
      redirect_to finance_batch_cooking_sessions_path,
                  alert: "Une écriture de cette session est rattachée à un décompte émis : " \
                         "elle ne peut plus être supprimée. Passe par une contre-écriture."
    end

    private

    # Écrit la session PUIS ses écritures, dans une seule transaction : une
    # session enregistrée dont les écritures ont échoué serait invisible et
    # fausse à la fois.
    def save_and_record
      cuisiniers = resolve_cooks
      rapport = nil

      ApplicationRecord.transaction do
        yield
        sync_servings
        sync_cooks(cuisiniers)
        rapport = Finance::RecordBatchCooking.new(session: @session,
                                                  whodunnit: current_user&.email).run!
      end

      redirect_to finance_batch_cooking_sessions_path,
                  notice: "Session enregistrée — #{rapport.summary}."
    rescue ServiceError, ActiveRecord::RecordInvalid => e
      flash.now[:alert] = e.message
      prepare_form
      render(@session.persisted? ? :edit : :new, status: :unprocessable_entity)
    end

    # Les portions par ménage, telles que le formulaire les envoie :
    # `servings[<member_account_id>] = portions`. Une case vide ou nulle retire
    # la ligne — c'est le même geste que sur les fiches papier.
    def sync_servings
      voulues = submitted_servings

      @session.servings.each do |serving|
        portions = voulues.delete(serving.member_account_id)
        portions.to_i.positive? ? serving.update!(portions: portions) : serving.destroy!
      end

      voulues.each { |account_id, portions| @session.servings.create!(member_account_id: account_id, portions: portions) }
      @session.reload
    end

    def sync_cooks(cuisiniers)
      voulus = cuisiniers.index_by { |cook| cook[:human_id] }

      @session.cooks.each do |cook|
        attendu = voulus.delete(cook.human_id)
        attendu ? cook.update!(portions: attendu[:portions]) : cook.destroy!
      end

      voulus.each_value { |attrs| @session.cooks.create!(attrs) }
      @session.reload
    end

    # Une matrice de saisie n'a pas de forme fixe — une clé par compte, une par
    # membre : `permit` ne sait rien en dire d'utile. On la lit brute, comme
    # l'encodage des fiches papier, et chaque valeur est convertie ici.
    def raw_hash(value)
      return {} if value.blank?

      value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value.to_h
    end

    def submitted_servings
      raw_hash(params[:servings]).filter_map do |account_id, raw|
        portions = raw.to_s.strip.to_i
        [account_id.to_i, portions] if portions.positive?
      end.to_h
    end

    # Traduit les membres de ménage cochés en cuisiniers payables. Un membre
    # sans `human_id` arrête la saisie avec un message qui dit quoi faire —
    # jamais un formulaire qui « ne dit rien ».
    def resolve_cooks
      soumis = raw_hash(params[:cooks])
      selectionnes = soumis.select { |_id, attrs| attrs.is_a?(Hash) && attrs["selected"].to_s == "1" }
      return [] if selectionnes.empty?

      membres = HouseholdMember.where(id: selectionnes.keys.map(&:to_i)).index_by(&:id)
      manquants = membres.values.select { |membre| membre.human_id.blank? }

      if manquants.any?
        raise ServiceError,
              "#{manquants.map(&:name).to_sentence} #{manquants.one? ? "n'existe" : "n'existent"} pas " \
              "encore comme personne, et un compte ne s'ouvre qu'à une personne. " \
              "Crée-la depuis Équipe, puis reprends la session."
      end

      selectionnes.filter_map do |id, attrs|
        membre = membres[id.to_i]
        next unless membre

        { human_id: membre.human_id, portions: portions_of(attrs["portions"]) }
      end
    end

    def portions_of(raw)
      value = raw.to_s.strip.tr(",", ".")
      return 0 unless value.match?(/\A\d+(\.\d+)?\z/)

      BigDecimal(value)
    end

    # Ce que le formulaire propose : les comptes de ménage actifs, et les
    # membres de ménage présents à la date de la session — enfants compris, ce
    # sont eux qui cuisinent le plus souvent.
    def prepare_form
      date = @session.cooked_on || Date.current

      @accounts = MemberAccount.actives.where(kind: "household")
                               .includes(:household).ordered.to_a
      @members = HouseholdMember.active_on(date).includes(:household).ordered.to_a
      @serving_price_cents = Pricing::Rates.cents(Finance::RecordBatchCooking::SERVING_RATE_KEY, on: date)
      @cook_price_cents = Pricing::Rates.cents(Finance::RecordBatchCooking::COOK_RATE_KEY, on: date)
      @selected_servings = existing_servings
      @selected_cooks = existing_cooks
    end

    def existing_servings
      @session.servings.each_with_object({}) { |serving, memo| memo[serving.member_account_id] = serving.portions }
    end

    # Indexé par membre de ménage, pas par humain : c'est ce que le formulaire
    # coche.
    def existing_cooks
      par_humain = @session.cooks.each_with_object({}) { |cook, memo| memo[cook.human_id] = cook.portions }
      return {} if par_humain.empty?

      HouseholdMember.where(human_id: par_humain.keys)
                     .each_with_object({}) { |membre, memo| memo[membre.id] = par_humain[membre.human_id] }
    end

    # Les totaux de la liste, en UNE requête plutôt qu'une par session.
    def entries_by_session(sessions)
      return {} if sessions.empty?

      cles = sessions.map { |seance| "#{Finance::RecordBatchCooking::KEY_PREFIX}:#{seance.id}:%" }
      condition = cles.map { "idempotency_key LIKE ?" }.join(" OR ")

      AccountEntry.unscoped.where(condition, *cles).group_by do |entry|
        entry.idempotency_key.split(":")[1].to_i
      end
    end

    def supprimer_ecritures
      AccountEntry.unscoped
                  .where("idempotency_key LIKE ?", "#{Finance::RecordBatchCooking::KEY_PREFIX}:#{@session.id}:%")
                  .each(&:destroy!)
    end

    def get_session
      @session = BatchCookingSession.find(params[:id])
    end

    def session_params
      params.require(:batch_cooking_session).permit(:cooked_on, :notes)
    end

    def finance_secondary = "batch_cooking"
  end
end
