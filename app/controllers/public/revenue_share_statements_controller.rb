module Public
  # La page publique d'un relevé de reversement, atteinte par son jeton
  # (issue #247).
  #
  # Les propriétaires de la tiny house n'ont pas de compte Claudy et n'en auront
  # pas : le lien du mail doit s'ouvrir sur leur téléphone, sans session. Page en
  # français uniquement, libellés en dur — même raison que la page des décomptes
  # sourciers : rien sous le scope `public.*`, qui exigerait NL et EN.
  class RevenueShareStatementsController < ActionController::Base
    layout "print"

    def show
      @statement = RevenueShareStatement.find_by(token: params[:token])
      return render :invalid, status: :not_found if @statement.nil?

      @agreement = @statement.revenue_share_agreement
      @lines = @statement.revenue_share_statement_lines.chronological
    end
  end
end
