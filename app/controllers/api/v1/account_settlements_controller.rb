module Api
  module V1
    # Règlements reçus sur un compte courant (#193).
    #
    # Passe par `Finance::RecordSettlement`, le MÊME service que l'écran. On
    # hérite donc de sa règle : UN règlement = UNE écriture négative + UN
    # `AccountSettlement` qui la documente. Réécrire cette mécanique ici
    # produirait tôt ou tard deux façons de solder un compte, et donc deux
    # soldes.
    #
    # Pourquoi cet endpoint existe : reprendre quatre ans de consommation sans
    # reprendre les versements fabriquerait une dette fantôme de plusieurs
    # milliers d'euros sur des comptes qui, eux, ont bien été soldés chaque mois.
    #
    # `reference` sert de clé d'idempotence : la reprise l'alimente avec le mois
    # de la fiche réglée, et reposter le même règlement renvoie l'existant en 200
    # au lieu d'encaisser deux fois.
    class AccountSettlementsController < BaseController
      before_action :get_account

      def index
        @account_settlements = paginate(@member_account.account_settlements.recent_first)
      end

      def create
        attributes = settlement_params

        # `RecordSettlement` prend la valeur absolue du montant : un règlement
        # est par nature positif. Sur un import de masse, ça transformerait
        # silencieusement une erreur de signe en encaissement. On refuse plutôt.
        if attributes[:amount_cents].to_i <= 0
          return render json: { error: "unprocessable_entity",
                                message: "Le montant d'un règlement doit être strictement positif." },
                        status: :unprocessable_entity
        end

        existing = attributes[:reference].present? &&
                   @member_account.account_settlements.find_by(reference: attributes[:reference])
        if existing
          @account_settlement = existing
          return render :show, status: :ok
        end

        @account_settlement = Finance::RecordSettlement.new(
          member_account: @member_account,
          amount_cents: attributes[:amount_cents],
          received_on: attributes[:received_on],
          method: attributes[:method].presence || "bank_transfer",
          received_channel: attributes[:received_channel].presence || "bank",
          reference: attributes[:reference],
          notes: attributes[:notes],
          whodunnit: "api:agent"
        ).run!

        render :show, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e.record)
      end

      private

      def get_account
        @member_account = MemberAccount.find(params[:member_account_id])
      end

      def settlement_params
        params.require(:account_settlement).permit(:amount_cents, :received_on, :method,
                                                   :received_channel, :reference, :notes)
      end
    end
  end
end
