module Api
  module V1
    # L'écriture d'à-nouveau d'un exercice (#196).
    #
    # C'est la seule écriture comptable que l'API peut poser, et elle a sa propre
    # route plutôt qu'un `POST /journal_entries` générique — parce que la règle
    # du lot B tient précisément à ça : *la double écriture se génère, elle ne se
    # saisit jamais*. Une écriture d'ouverture est l'exception qui confirme la
    # règle : elle ne dérive d'aucun document métier de claudy, elle vient d'un
    # bilan produit ailleurs.
    #
    # Le contrôle qui compte est l'ÉQUILIBRE. Un à-nouveau qui ne balance pas
    # contamine tout l'exercice : la balance ment dès la première ligne et plus
    # rien de ce qu'on comptabilise ensuite n'est interprétable. On refuse, avec
    # l'écart en clair.
    #
    # Idempotence par CONTRE-PASSATION, pas par écrasement : un exercice ne porte
    # qu'une écriture d'ouverture, et la reposter contre-passe l'ancienne avant
    # d'en écrire une nouvelle. Modifier une écriture passée est exactement ce
    # que `JournalEntry` interdit, et pour de bonnes raisons.
    class OpeningEntriesController < BaseController
      def index
        scope = JournalEntry.where(journal: "opening").order(:entry_date, :number).includes(:fiscal_year)
        scope = scope.where(fiscal_year_id: params[:fiscal_year_id]) if params[:fiscal_year_id].present?

        @journal_entries = paginate(scope)
      end

      def create
        fiscal_year = FiscalYear.find(params.require(:fiscal_year_id))
        return render_closed(fiscal_year) if fiscal_year.status == "closed"

        lines = build_lines
        return if performed?

        écart = lines.sum { |l| l[:debit_cents] } - lines.sum { |l| l[:credit_cents] }
        return render_unbalanced(écart) unless écart.zero?

        ApplicationRecord.transaction do
          reverse_previous(fiscal_year)

          @journal_entry = Accounting::PostDocument.new(
            legal_entity: fiscal_year.legal_entity,
            journal: "opening",
            entry_date: entry_date_for(fiscal_year),
            label: params[:label].presence || "À-nouveau #{fiscal_year.starts_on.year}",
            lines: lines,
            whodunnit: "api:agent"
          ).run!
        end

        render :show, status: :created
      rescue Accounting::PostDocument::MissingFiscalYear => e
        render json: { error: "unprocessable_entity", message: e.message }, status: :unprocessable_entity
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e.record)
      end

      private

      # Les lignes sont adressées par CODE de compte, jamais par identifiant :
      # un à-nouveau se lit dans un bilan, et un bilan porte des numéros de
      # compte. Un code inconnu arrête tout — poser un à-nouveau amputé d'une
      # ligne serait pire que ne rien poser, puisqu'il balancerait quand même
      # après suppression d'un couple.
      def build_lines
        params.require(:lines).map do |line|
          code = line[:general_account_code].to_s
          account = GeneralAccount.find_by(code: code)
          if account.nil?
            render json: { error: "unprocessable_entity",
                           message: "Compte général inconnu : #{code}. Crée-le avant de poser l'à-nouveau." },
                   status: :unprocessable_entity
            return []
          end

          # Un axe analytique inconnu est refusé plutôt qu'ignoré : une ligne
          # qui perd son axe en silence rend la balance analytique fausse sans
          # que rien ne le signale, et c'est le pire des deux mondes.
          analytic = nil
          if line[:analytic_account_code].present?
            analytic = AnalyticAccount.find_by(code: line[:analytic_account_code])
            if analytic.nil?
              render json: { error: "unprocessable_entity",
                             message: "Axe analytique inconnu : #{line[:analytic_account_code]}." },
                     status: :unprocessable_entity
              return []
            end
          end

          { account: account, analytic_account: analytic,
            debit_cents: line[:debit_cents].to_i, credit_cents: line[:credit_cents].to_i,
            label: line[:label].presence }
        end
      end

      # L'à-nouveau est daté du PREMIER jour de l'exercice : c'est ce qui le fait
      # tomber avant tout mouvement, dans la balance comme dans le grand livre.
      def entry_date_for(fiscal_year)
        params[:entry_date].present? ? Date.parse(params[:entry_date]) : fiscal_year.starts_on
      end

      def reverse_previous(fiscal_year)
        déjà_contre_passées = JournalEntry.where(fiscal_year_id: fiscal_year.id, journal: "opening")
                                          .where.not(reversal_of_id: nil).pluck(:reversal_of_id)

        JournalEntry.where(fiscal_year_id: fiscal_year.id, journal: "opening").find_each do |previous|
          # On saute les contre-passations elles-mêmes ET celles déjà annulées :
          # au troisième dépôt, `ReverseEntry` lèverait sinon `AlreadyReversed`
          # sur la toute première écriture, et l'appelant récolterait une 500.
          next if previous.reversal_of_id.present?
          next if déjà_contre_passées.include?(previous.id)

          Accounting::ReverseEntry.new(journal_entry: previous, entry_date: previous.entry_date,
                                       whodunnit: "api:agent").run!
        end
      end

      def render_unbalanced(écart)
        render json: {
          error: "unprocessable_entity",
          message: "À-nouveau déséquilibré de #{Money.new(écart).format} : les débits ne font pas les crédits. " \
                   "Une ouverture qui ne balance pas contamine tout l'exercice.",
          imbalance_cents: écart
        }, status: :unprocessable_entity
      end

      def render_closed(fiscal_year)
        render json: {
          error: "conflict",
          message: "Exercice ##{fiscal_year.id} clôturé : on n'y pose plus d'à-nouveau.",
          fiscal_year_id: fiscal_year.id
        }, status: :conflict
      end
    end
  end
end
