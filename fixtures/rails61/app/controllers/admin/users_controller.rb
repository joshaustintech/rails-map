module Admin
  class UsersController
    def show
      render template: "shared/user"
    end

    def dynamic
      render template_name, layout: "bare"
    end

    def response
      render(json: { ready: true })
    end

    def layout_only
      render layout: "bare", locals: { name: "Ada" }
    end

    def mixed_render
      render template: "shared/user", layout: "bare"
      render template_name
    end
  end
end
