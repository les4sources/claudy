module Public
  # Douze mois de compte, pour la personne dont c'est le compte.
  #
  # Même porte d'entrée que le décompte mensuel : le jeton reçu par mail. Un
  # habitant des 4 Sources n'a pas de compte Claudy et n'en aura pas — lui
  # demander de se connecter reviendrait à ne pas publier la page.
  #
  # Le jeton donne accès au compte, pas au seul mois : c'est un élargissement
  # assumé par rapport au décompte, et la raison pour laquelle la page ne
  # montre que des agrégats du compte lui-même — rien du lieu, rien des autres.
  #
  # FRANÇAIS UNIQUEMENT, libellés en dur, comme la page décompte : les quinze
  # sourciers du lieu ne sont pas les clients internationaux du funnel.
  class RetrospectivesController < ActionController::Base
    layout "public"

    def show
      statement = AccountStatement.find_by(token: params[:token])
      return render "public/statements/invalid", status: :not_found if statement.nil?

      @account = statement.member_account
      @statement = statement
      @retrospective = MemberAccounts::Retrospective.new(@account)
    end
  end
end
