module Accounting
  # Comptabilise une ligne de trésorerie entièrement affectée.
  #
  # C'est ici que la promesse du lot devient visible : la compta a ventilé un
  # virement en deux gestes — « 800 € d'hébergement pour le pôle Accueil, 500 €
  # de salle pour le pôle Technique » — et l'écriture en partie double sort
  # toute seule, avec le bon sens de chaque côté. Personne n'a tapé un débit.
  #
  # Le sens suit le signe : un encaissement débite la trésorerie et crédite les
  # comptes affectés ; un décaissement fait l'inverse.
  #
  # **L'entité de l'allocation a un effet comptable réel.** Une facture de
  # travaux de la Société simple payée depuis le compte de la Fondation produit
  # DEUX écritures : chez la Fondation, l'argent sort contre un compte courant
  # inter-entités ; chez la Société simple, la charge est enregistrée contre ce
  # même compte courant, en sens inverse. C'est la seule façon de dire « mouvement
  # Fondation, charge Société simple » sans mentir dans l'un des deux jeux de
  # comptes — et le compte courant matérialise la dette entre les deux, qui
  # existe vraiment.
  class PostCashEntry < ServiceBase
    class NotFullyAllocated < StandardError; end
    class AlreadyPosted < StandardError; end
    class NotPostable < StandardError; end
    class TooManyEntities < StandardError; end

    def initialize(cash_entry:, whodunnit: nil)
      @entry = cash_entry
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { cash_entry: @entry.id }) { post }
    end

    def run!
      post
    end

    private

    def post
      # Verrou et re-tests DANS la transaction : sans lui, une allocation peut
      # être retirée entre le contrôle de couverture et la création de
      # l'écriture, et la ligne finirait « comptabilisée » sur un état qui
      # n'existe plus.
      ApplicationRecord.transaction do
        @entry.lock!

        raise AlreadyPosted, "Cette ligne est déjà comptabilisée." if @entry.reload.posted?
        raise NotPostable, "Cette ligne est exclue — elle ne se comptabilise pas." if @entry.status == "excluded"

        unless @entry.fully_allocated?
          raise NotFullyAllocated,
                "Il reste #{Money.new(@entry.remaining_cents, 'EUR').format} à affecter sur cette ligne."
        end

        allocations = @entry.cash_allocations.includes(:general_account, :legal_entity).to_a
        raise NotFullyAllocated, "Cette ligne n'a aucune allocation." if allocations.empty?

        journal_entry = post_treasury_side(allocations)
        post_foreign_side(allocations)

        @entry.update!(status: "allocated", allocated_at: Time.current)
        journal_entry
      end
    end

    def treasury_entity = @entry.cash_account.legal_entity

    def own_allocations(allocations)
      allocations.select { |a| a.legal_entity_id == treasury_entity.id }
    end

    def foreign_allocations(allocations)
      allocations.reject { |a| a.legal_entity_id == treasury_entity.id }
    end

    # L'écriture du côté où l'argent a bougé. Les allocations d'une autre entité
    # y apparaissent en une seule ligne de compte courant : chez la Fondation,
    # payer une charge de la Société simple crée une créance sur elle, pas une
    # charge.
    def post_treasury_side(allocations)
      lines = treasury_line + allocation_lines(own_allocations(allocations), incoming: @entry.incoming?)

      etrangeres = foreign_allocations(allocations)
      if etrangeres.any?
        total = etrangeres.sum { |a| a.amount_cents.abs }
        side = @entry.incoming? ? { credit_cents: total } : { debit_cents: total }
        lines += [{ account: current_account, label: "Compte courant #{entities_label(etrangeres)}" }.merge(side)]
      end

      PostDocument.new(
        legal_entity: treasury_entity,
        journal: @entry.journal,
        entry_date: @entry.entry_date,
        label: @entry.label,
        source: @entry,
        whodunnit: @whodunnit,
        lines: lines
      ).run!
    end

    # L'écriture miroir chez l'entité à qui la charge (ou le produit) appartient.
    def post_foreign_side(allocations)
      etrangeres = foreign_allocations(allocations)
      return if etrangeres.empty?

      entites = etrangeres.map(&:legal_entity).uniq
      if entites.size > 1
        raise TooManyEntities,
              "Cette ligne mêle #{entites.size} entités tierces — découpe-la en autant de lignes, " \
              "sinon leurs comptes courants deviennent illisibles."
      end

      entite = entites.first
      total = etrangeres.sum { |a| a.amount_cents.abs }
      # Sens inversé par rapport à la trésorerie : chez elle, la charge est bien
      # une charge, et la contrepartie est sa dette envers l'entité payeuse.
      contrepartie = @entry.incoming? ? { debit_cents: total } : { credit_cents: total }

      PostDocument.new(
        legal_entity: entite,
        journal: "misc",
        entry_date: @entry.entry_date,
        label: "#{@entry.label} — via #{treasury_entity.name}",
        source: @entry,
        whodunnit: @whodunnit,
        lines: allocation_lines(etrangeres, incoming: @entry.incoming?) +
               [{ account: current_account, label: "Compte courant #{treasury_entity.name}" }.merge(contrepartie)]
      ).run!
    end

    def treasury_line
      account = @entry.cash_account.general_account
      montant = @entry.amount_cents.abs
      side = @entry.incoming? ? { debit_cents: montant } : { credit_cents: montant }

      [{ account: account, label: @entry.label }.merge(side)]
    end

    def allocation_lines(allocations, incoming:)
      allocations.map do |allocation|
        montant = allocation.amount_cents.abs
        side = incoming ? { credit_cents: montant } : { debit_cents: montant }

        {
          account: allocation.general_account,
          analytic_account: allocation.analytic_account,
          team: allocation.team,
          label: allocation.label.presence || @entry.label
        }.merge(side)
      end
    end

    def current_account
      @current_account ||= GeneralAccount.find_by(code: GeneralAccount::INTER_ENTITY_CODE) ||
                           raise(NotPostable,
                                 "Le compte courant inter-entités #{GeneralAccount::INTER_ENTITY_CODE} " \
                                 "n'existe pas — lance `rake accounting:seed_reference`.")
    end

    def entities_label(allocations)
      allocations.map { |a| a.legal_entity.name }.uniq.join(", ")
    end
  end
end
