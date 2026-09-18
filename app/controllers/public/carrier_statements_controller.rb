module Public
  # La page publique d'un relevé de porteur, atteinte par son jeton (epic #244,
  # phase 3).
  #
  # Un porteur d'activité n'a pas forcément de compte Claudy : le lien du mail
  # doit s'ouvrir sur son téléphone, sans session. Page en français uniquement,
  # libellés en dur — même raison que les reversements et les décomptes
  # sourciers : rien sous le scope `public.*`, qui exigerait NL et EN.
  class CarrierStatementsController < ActionController::Base
    layout "print"

    def show
      @statement = CarrierStatement.find_by(token: params[:token])
      return render :invalid, status: :not_found if @statement.nil?

      @human = @statement.human
      @lines = @statement.carrier_statement_lines.chronological
    end
  end
end
