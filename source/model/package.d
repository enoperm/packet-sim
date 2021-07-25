module model;

public import model.abb;
public import model.common;
public import model.pupd;
public import model.spring;
public import model.static_;

// TODO: make forwarding more generic.
public:
static foreach(mod; ["abb", "pupd", "spring", "static_"]) {
    mixin(`public import model.` ~ mod ~ `;`);
    mixin(`alias setup_` ~ mod ~ ` = model.` ~ mod ~ `.setup_` ~ mod ~ `;`);
}
