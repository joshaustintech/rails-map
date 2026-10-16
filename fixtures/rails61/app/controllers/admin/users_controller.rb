module Admin
  class UsersController
    def show
      render template: "shared/user"
    end

    def dynamic
      render template_name
    end

    def response
      render(json: { ready: true })
    end

    def layout_only
      render layout: "bare"
    end
  end
end
