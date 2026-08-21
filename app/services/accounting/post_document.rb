module Accounting
  # Le SEUL chemin de création d'une écriture comptable.
  #
  # On lui passe un document métier et la ventilation qu'un humain a validée ;
  # il produit les deux côtés. C'est la traduction en code de la règle qui
  # décide du succès du lot B : *la double écriture se génère, elle ne se
  # saisit jamais*. Ce qui a fait échouer le système actuel n'est pas son
  # modèle comptable — c'est que les gens ne remplissent pas. Doubler la charge
  # de saisie garantirait le même échec.
  #
  # Aucun contrôleur n'appelle `JournalEntry.create`. L'anti-critère est
  # vérifiable : `rg 'JournalEntry\.(new|create)' app/controllers/` doit rester
  # vide.
  #
  # Idempotence : repasser le même document dans le même journal retourne
  # l'écriture existante au lieu d'en créer une seconde. L'index unique sur
  # (source_type, source_id, journal) le garantit même en concurrence.
  class PostDocument < ServiceBase
    class MissingFiscalYear < StandardError; end

    # `lines` est un tableau de hash :
    #   { account: <GeneralAccount|code>, debit_cents: / credit_cents:,
    #     analytic_account:, team:, third_party:, label: }
    def initialize(legal_entity:, journal:, entry_date:, label:, lines:,
                   source: nil, whodunnit: nil)
      @legal_entity = legal_entity
      @journal = journal.to_s
      @entry_date = entry_date
      @label = label
      @lines = lines
      @source = source
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { journal: @journal }) { post }
    end

    def run!
      post
    end

    private

    def post
      existing = existing_entry
      return existing if existing

      fiscal_year = @legal_entity.fiscal_year_for(@entry_date)
      if fiscal_year.blank?
        raise MissingFiscalYear,
              "Aucun exercice ouvert ne couvre le #{I18n.l(@entry_date)} pour #{@legal_entity.name} — " \
              "crée l'exercice avant de comptabiliser."
      end

      PaperTrail.request(whodunnit: @whodunnit || "accounting") do
        ApplicationRecord.transaction do
          # Le verrou est sur l'EXERCICE et il précède le calcul du numéro :
          # `MAX(number) + 1` sans verrou donne le même numéro à deux passations
          # concurrentes, et l'index unique en fait échouer une au hasard.
          fiscal_year.lock!

          entry = JournalEntry.new(
            fiscal_year: fiscal_year,
            legal_entity: @legal_entity,
            journal: @journal,
            number: next_number(fiscal_year),
            entry_date: @entry_date,
            label: @label,
            source: @source,
            posted_at: Time.current,
            whodunnit: @whodunnit
          )

          @lines.each { |attributes| entry.journal_lines.build(line_attributes(attributes)) }
          entry.save!
          entry
        end
      end
    rescue ActiveRecord::RecordNotUnique
      # Deux passations concurrentes du même document : l'index unique a tranché,
      # on rend celle qui a gagné plutôt que de faire échouer l'appelant.
      existing_entry or raise
    end

    def existing_entry
      return nil if @source.blank?

      JournalEntry.find_by(source: @source, journal: @journal)
    end

    def line_attributes(attributes)
      account = attributes[:account]
      account = GeneralAccount.find_by!(code: account.to_s) unless account.is_a?(GeneralAccount)

      {
        general_account: account,
        analytic_account: attributes[:analytic_account],
        third_party: attributes[:third_party],
        team: attributes[:team],
        debit_cents: attributes[:debit_cents].to_i,
        credit_cents: attributes[:credit_cents].to_i,
        label: attributes[:label]
      }
    end

    # La numérotation est prise sur le maximum existant, soft-deletés compris :
    # un numéro n'est jamais réattribué, sinon la séquence ment sur ce qui a
    # existé. L'appelant a verrouillé l'exercice avant d'arriver ici.
    def next_number(fiscal_year)
      highest = JournalEntry.with_deleted do
        JournalEntry.where(fiscal_year_id: fiscal_year.id, journal: @journal).maximum(:number)
      end
      highest.to_i + 1
    end
  end
end
