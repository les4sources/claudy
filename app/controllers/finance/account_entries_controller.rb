module Finance
  # Écritures manuelles depuis la fiche d'un compte (issue #155).
  #
  # La suppression d'une écriture verrouillée est refusée avec un message clair :
  # `AccountEntry` lève `AccountEntry::Locked`, on la rattrape ici pour ne pas
  # servir une 500 à la comptabilité.
  class AccountEntriesController < Finance::BaseController
    before_action :get_account

    def create
      @entry = @account.account_entries.new(entry_params)

      if @entry.save
        redirect_to finance_account_path(@account), notice: "L'écriture a été ajoutée."
      else
        redirect_to finance_account_path(@account),
                    alert: @entry.errors.full_messages.to_sentence.presence || "L'écriture n'a pas pu être ajoutée."
      end
    end

    def destroy
      entry = @account.account_entries.find(params[:id])
      entry.soft_delete!(validate: false)
      redirect_to finance_account_path(@account), notice: "L'écriture a été supprimée."
    rescue AccountEntry::Locked => e
      redirect_to finance_account_path(@account), alert: e.message
    end

    private

    def get_account
      @account = MemberAccount.find(params[:account_id])
    end

    def entry_params
      params.require(:account_entry)
            .permit(:entry_date, :label, :flow, :kind, :quantity, :source)
            .merge(amount_cents: submitted_amount_cents)
    end

    # Saisi en euros, signé : positif = dû par le compte, négatif = en sa faveur.
    # Une saisie vide ou non numérique retombe sur 0, que la base refuse — plutôt
    # qu'un montant inventé.
    def submitted_amount_cents
      raw = params.dig(:account_entry, :amount).to_s.strip.tr(",", ".")
      return 0 unless raw.match?(/\A-?\d+(\.\d+)?\z/)

      (raw.to_f * 100).round
    end
  end
end
