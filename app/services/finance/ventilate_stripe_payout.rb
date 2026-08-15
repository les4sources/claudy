module Finance
  # Ventile un versement Stripe en somme algébrique : recettes d'un côté, frais
  # de l'autre, pour un total exactement égal au net reçu (issue #187).
  #
  # C'est ce qui remplace l'« opération diverse » saisie à la main. Une ligne
  # bancaire de 1 243,17 € ne correspond à aucune facture — elle est la somme de
  # plusieurs paiements moins des commissions. Tant qu'on ne sait pas dire de
  # quoi, on ne peut ni comptabiliser proprement ni savoir ce que coûte le fait
  # d'être payé par carte.
  #
  # **La commission suit le pôle qui l'a générée.** La commission d'un paiement
  # rattaché à un séjour se répartit au prorata des recettes de ce séjour, avec
  # le même répartiteur que la ventilation des séjours. Sans ça, tout le coût
  # d'encaissement atterrit en bloc sur l'administratif, et l'hébergement a
  # l'air plus rentable qu'il ne l'est.
  class VentilateStripePayout < ServiceBase
    class Unbalanced < StandardError; end
    class MissingMapping < StandardError; end

    FEE_ACCOUNT_CODE = "618000".freeze

    Line = Struct.new(:label, :amount_cents, :general_account, :team, :document, keyword_init: true)

    def initialize(payout:)
      @payout = payout
    end

    def run
      catch_error(context: { payout: @payout.id }) { ventilate }
    end

    def run!
      ventilate
    end

    private

    def ventilate
      unless @payout.balanced?
        ecart = @payout.transactions_net_cents - @payout.amount_cents
        raise Unbalanced,
              "Versement #{@payout.stripe_id} : ses transactions totalisent " \
              "#{money(@payout.transactions_net_cents)} pour un net de #{money(@payout.amount_cents)}. " \
              "Écart de #{money(ecart)} — il manque des transactions."
      end

      lignes = revenue_lines + fee_lines
      total = lignes.sum(&:amount_cents)

      # Ceinture et bretelles : l'invariant du versement est vérifié en amont,
      # mais c'est la somme des LIGNES qui entrera au journal.
      unless total == @payout.amount_cents
        raise Unbalanced,
              "La ventilation totalise #{money(total)} pour un versement de #{money(@payout.amount_cents)}."
      end

      lignes
    end

    # Chaque encaissement à son compte de recette. Quand le paiement pointe un
    # séjour, on réutilise la ventilation par catégorie : un paiement de séjour
    # n'est pas une recette indifférenciée.
    def revenue_lines
      @payout.component_transactions.revenue.includes(payment: :stay).flat_map do |transaction|
        stay = transaction.stay
        brut = transaction.gross_cents

        if stay.present?
          begin
            VentilateStay.new(stay: stay, amount_cents: brut).run!.map do |ligne|
              Line.new(label: "#{ligne.label} (Stripe)", amount_cents: ligne.amount_cents,
                       general_account: ligne.general_account, team: ligne.team, document: stay)
            end
          rescue VentilateStay::EmptyQuote, VentilateStay::MissingMapping
            [fallback_revenue_line(transaction, brut)]
          end
        else
          [fallback_revenue_line(transaction, brut)]
        end
      end
    end

    # Les frais, en NÉGATIF : c'est ce qui fait de l'ensemble une somme
    # algébrique dont le total est le net. Un frais rattaché à un séjour se
    # répartit au prorata de ses recettes ; sinon il reste en bloc, non affecté.
    def fee_lines
      commissions + standalone_costs
    end

    # Les frais facturés à part — l'abonnement mensuel, une contestation. Ils ne
    # portent pas de `fee` : leur net EST le coût, en négatif. Sans cette
    # branche, ils disparaissaient de la ventilation et le total ne refermait
    # plus le versement. Constaté sur un jeu de données réaliste avant la revue.
    def standalone_costs
      @payout.component_transactions.where.not(kind: StripeBalanceTransaction::REVENUE_KINDS)
             .filter_map do |transaction|
        next if transaction.net_cents.zero?

        Line.new(label: transaction.description.presence || "Frais Stripe",
                 amount_cents: transaction.net_cents, general_account: fee_account,
                 team: nil, document: nil)
      end
    end

    def commissions
      @payout.component_transactions.revenue.includes(payment: :stay).flat_map do |transaction|
        frais = transaction.fee_cents
        next [] if frais.zero?

        stay = transaction.stay
        if stay.present?
          parts = begin
            VentilateStay.new(stay: stay, amount_cents: frais).run!
          rescue VentilateStay::EmptyQuote, VentilateStay::MissingMapping
            nil
          end

          if parts.present?
            next parts.map do |part|
              Line.new(label: "Commission Stripe — #{part.label}", amount_cents: -part.amount_cents,
                       general_account: fee_account, team: part.team, document: stay)
            end
          end
        end

        [Line.new(label: "Commission Stripe", amount_cents: -frais, general_account: fee_account,
                  team: nil, document: nil)]
      end
    end

    def fallback_revenue_line(transaction, brut)
      Line.new(label: transaction.description.presence || "Encaissement Stripe",
               amount_cents: brut, general_account: default_revenue_account, team: nil,
               document: transaction.payment)
    end

    def fee_account
      @fee_account ||= GeneralAccount.find_by(code: FEE_ACCOUNT_CODE) ||
                       raise(MissingMapping, "Le compte de frais bancaires #{FEE_ACCOUNT_CODE} n'existe pas.")
    end

    # Pas de compte « par défaut » caché : celui-ci est explicite, nommé, et sert
    # uniquement quand l'encaissement ne pointe aucun séjour. Une recette qui
    # atterrit là se voit.
    def default_revenue_account
      @default_revenue_account ||= RevenueMapping.find_by(category: "lodging")&.general_account ||
                                   raise(MissingMapping, "Aucune correspondance de recette configurée.")
    end

    def money(cents) = Money.new(cents, "EUR").format
  end
end
