module Public
  # Page publique d'un décompte, atteinte par son jeton (issue #160).
  #
  # Aucune session, aucun Devise : le lien du mail doit s'ouvrir sur le
  # téléphone d'un sourcier qui n'a pas de compte dans Claudy — et il n'en aura
  # pas avant le lot E.
  #
  # La page est EN FRANÇAIS UNIQUEMENT, libellés en dur. On n'ajoute surtout pas
  # de clés sous le scope `public.*` : `spec/i18n/public_locales_parity_spec.rb`
  # exigerait alors les traductions NL et EN, alors que cette page s'adresse aux
  # quinze sourciers du lieu, pas aux clients internationaux.
  class StatementsController < ActionController::Base
    layout "print"

    def show
      @statement = AccountStatement.find_by(token: params[:token])
      return render :invalid, status: :not_found if @statement.nil?

      @account = @statement.member_account
      @entries = @statement.account_entries.chronological
    end
  end
end
