###**
Linking to fragments
====================

The `up.link` module lets you build links that update fragments instead of entire pages.

\#\#\# Motivation

In a traditional web application, the entire page is destroyed and re-created when the
user follows a link:

![Traditional page flow](/images/tutorial/fragment_flow_vanilla.svg){:width="620" class="picture has_border is_sepia has_padding"}

This makes for an unfriendly experience:

- State changes caused by AJAX updates get lost during the page transition.
- Unsaved form changes get lost during the page transition.
- The JavaScript VM is reset during the page transition.
- If the page layout is composed from multiple scrollable containers
  (e.g. a pane view), the scroll positions get lost during the page transition.
- The user sees a "flash" as the browser loads and renders the new page,
  even if large portions of the old and new page are the same (navigation, layout, etc.).

Unpoly fixes this by letting you annotate links with an [`up-target`](/a-up-follow#up-target)
attribute. The value of this attribute is a CSS selector that indicates which page
fragment to update. The server **still renders full HTML pages**, but we only use
the targeted fragments and discard the rest:

![Unpoly page flow](/images/tutorial/fragment_flow_unpoly.svg){:width="620" class="picture has_border is_sepia has_padding"}

With this model, following links feels smooth. All DOM state outside the updated fragment is preserved.
Pages also load much faster since the DOM, CSS and JavaScript environments do not need to be
destroyed and recreated for every request.


\#\#\# Example

Let's say we are rendering three pages with a tabbed navigation to switch between screens:

Your HTML could look like this:

```
<nav>
  <a href="/pages/a">A</a>
  <a href="/pages/b">B</a>
  <a href="/pages/b">C</a>
</nav>

<article>
  Page A
</article>
```

Since we only want to update the `<article>` tag, we annotate the links
with an `up-target` attribute:

```
<nav>
  <a href="/pages/a" up-target="article">A</a>
  <a href="/pages/b" up-target="article">B</a>
  <a href="/pages/b" up-target="article">C</a>
</nav>
```

Note that instead of `article` you can use any other CSS selector like `#main .article`.

With these [`up-target`](/a-up-follow#up-target) annotations Unpoly only updates the targeted part of the screen.
The JavaScript environment will persist and the user will not see a white flash while the
new page is loading.

@see a[up-follow]
@see a[up-instant]
@see a[up-preload]
@see up.follow

@module up.link
###

up.link = do ->

  u = up.util
  e = up.element

  linkPreloader = new up.LinkPreloader()

  lastMousedownTarget = null

  # Links with attribute-provided HTML are always followable.
  LINKS_WITH_LOCAL_HTML = ['a[up-content]', 'a[up-fragment]', 'a[up-document]']

  # Links with remote HTML are followable if there is one additional attribute
  # suggesting "follow me through Unpoly".
  LINKS_WITH_REMOTE_HTML = ['a[href]', '[up-href]']
  ATTRIBUTES_SUGGESTING_FOLLOW = ['[up-follow]', '[up-target]', '[up-layer]', '[up-transition]', '[up-preload]']

  combineFollowableSelectors = (elementSelectors, attributeSelectors) ->
    return u.flatMap(elementSelectors, (elementSelector) ->
      attributeSelectors.map((attributeSelector) -> elementSelector + attributeSelector)
    )

  ###**
  Configures defaults for link handling.

  In particular you can configure Unpoly to handle [all links on the page](/handling-everything)
  without requiring developers to set `[up-...]` attributes.

  @property up.link.config

  @param {Array<string>} config.followSelectors
    An array of CSS selectors matching links that will be [followed through Unpoly](/a-up-follow).

    You can customize this property to automatically follow *all* links on a page without requiring an `[up-follow]` attribute.
    See [Handling all links and forms](/handling-everything).

  @param {Array<string>} config.noFollowSelectors
    Exceptions to `config.followSelectors`.

    Matching links will *not* be [followed through Unpoly](/a-up-follow), even if they match `config.followSelectors`.

    By default Unpoly excludes:

    - Links with an `[up-follow=false]` attribute.
    - Links with a cross-origin `[href]`.
    - Links with a `[target]` attribute (to target an iframe or open new browser tab).
    - Links with a `[rel=download]` attribute.
    - Links with an `[href]` attribute starting with `javascript:`.
    - Links with an `[href="#"]` attribute that don't also have local HTML
      in an `[up-document]`, `[up-fragment]` or `[up-content]` attribute.

  @param {Array<string>} config.instantSelectors
    An array of CSS selectors matching links that are [followed on `mousedown`](/a-up-instant)
    instead of on `click`.

    You can customize this property to follow *all* links on `mousedown` without requiring an `[up-instant]` attribute.
    See [Handling all links and forms](/handling-everything).

  @param {Array<string>} config.noInstantSelectors
    Exceptions to `config.followSelectors`.

    Matching links will *not* be [followed through Unpoly](/a-up-follow), even if they match `config.followSelectors`.

    By default Unpoly excludes:

    - Links with an `[up-instant=false]` attribute.
    - Links that are [not followable](#config.noFollowSelectors).

  @param {Array<string>} config.preloadSelectors
    An array of CSS selectors matching links that are [preloaded on hover](/a-up-preload).

    You can customize this property to preload *all* links on `mousedown` without requiring an `[up-preload]` attribute.
    See [Handling all links and forms](/handling-everything).

  @param {Array<string>} config.noPreloadSelectors
    Exceptions to `config.preloadSelectors`.

    Matching links will *not* be [preloaded on hover](/a-up-preload), even if they match `config.preloadSelectors`.

    By default Unpoly excludes:

    - Links with an `[up-preload=false]` attribute.
    - Links that are [not followable](#config.noFollowSelectors).
    - When the link destination [cannot be cached](/up.network.config#config.autoCache).

  @param {number} [config.preloadDelay=75]
    The number of milliseconds to wait before [`[up-preload]`](/a-up-preload)
    starts preloading.

  @param {boolean|string} [config.preloadEnabled='auto']
    Whether Unpoly will load [preload requests](/a-up-preload).

    With the default setting (`"auto"`) Unpoly will load preload requests
    unless `up.network.shouldReduceRequests()` detects a poor connection.

    If set to `true`, Unpoly will always load preload links.

    If set to `false`, Unpoly will never preload links.

  @param {Array<string>} [config.clickableSelectors]
    A list of CSS selectors matching elements that should behave like links or buttons.

    @see [up-clickable]
  @stable
  ###
  config = new up.Config ->
    return {
      followSelectors: combineFollowableSelectors(LINKS_WITH_REMOTE_HTML, ATTRIBUTES_SUGGESTING_FOLLOW).concat(LINKS_WITH_LOCAL_HTML),
      # (1) We don't want to follow <a href="#anchor"> links without a path. Instead
      #     we will let the browser change the current location's anchor and up.reveal()
      #     on hashchange to scroll past obstructions.
      # (2) We want to follow links with [href=#] only if they have a local source of HTML
      #     through [up-content], [up-fragment] or [up-document].
      #     Many web developers are used to give JavaScript-handled links an [href="#"]
      #     attribute. Also frameworks like Bootstrap only style links if they have an [href].
      # (3) We don't want to handle <a href="javascript:foo()"> links.
      noFollowSelectors: ['[up-follow=false]', 'a[download]', 'a[target]', 'a[href^="#"]:not([up-content]):not([up-fragment]):not([up-document])', 'a[href^="javascript:"]']
      instantSelectors: ['[up-instant]'],
      noInstantSelectors: ['[up-instant=false]', '[onclick]'],
      preloadSelectors: combineFollowableSelectors(LINKS_WITH_REMOTE_HTML, ['[up-preload]']),
      noPreloadSelectors: ['[up-preload=false]'],
      clickableSelectors: LINKS_WITH_LOCAL_HTML.concat(['[up-emit]', '[up-accept]', '[up-dismiss]', '[up-clickable]']),
      preloadDelay: 90,
      preloadEnabled: 'auto' # true | false | 'auto'
    }

  fullFollowSelector = ->
    config.followSelectors.join(',')

  fullPreloadSelector = ->
    config.preloadSelectors.join(',')

  fullInstantSelector = ->
    config.instantSelectors.join(',')

  fullClickableSelector = ->
    config.clickableSelectors.join(',')

  ###**
  Returns whether the link was explicitly marked up as not followable,
  e.g. through `[up-follow=false]`.

  This differs from `config.followSelectors` in that we want users to configure
  simple selectors, but let users make exceptions. We also have a few built-in
  exceptions of our own, e.g. to never follow an `<a href="javascript:...">` link.

  @function isFollowDisabled
  @param {Element} link
  @return {boolean}
  ###
  isFollowDisabled = (link) ->
    return e.matches(link, config.noFollowSelectors.join(',')) || u.isCrossOrigin(link)

  isPreloadDisabled = (link) ->
    return !up.browser.canPushState() ||
      e.matches(link, config.noPreloadSelectors.join(',')) ||
      isFollowDisabled(link) ||
      !willCache(link)

  willCache = (link) ->
    # Instantiate a lightweight request with basic link attributes needed for the cache-check.
    options = parseRequestOptions(link)
    if options.url
      options.cache ?= 'auto'
      options.basic = true #
      request = new up.Request(options)
      return request.willCache()

  isInstantDisabled = (link) ->
    return e.matches(link, config.noInstantSelectors.join(',')) || isFollowDisabled(link)

  reset = ->
    lastMousedownTarget = null
    config.reset()
    linkPreloader.reset()

  ###**
  Follows the given link with JavaScript and updates a fragment with the server response.

  By default the layer's [main element](/up-main)
  will be replaced. Attributes like `a[up-target]`
  or `a[up-layer]` will be honored.

  Following a link is considered [navigation](/navigation) by default.

  Emits the event `up:link:follow`.

  \#\#\# Examples

  Assume we have a link with an `a[up-target]` attribute:

      <a href="/users" up-target=".main">Users</a>

  Calling `up.follow()` with this link will replace the page's `.main` fragment
  as if the user had clicked on the link:

      var link = document.querySelector('a')
      up.follow(link)

  @function up.follow

  @param {Element|jQuery|string} link
    The link to follow.

  @param {Object} [options]
    [Render options](/up.render) that should be used for following the link.

    Unpoly will parse render options from the given link's attributes
    like `[up-target]` or `[up-transition]`. See `a[up-follow]` for a list
    of supported attributes.

    You may pass this additional `options` object to supplement or override
    options parsed from the link attributes.

  @return {Promise<up.RenderResult>}
    A promise that will be fulfilled when the link destination
    has been loaded and rendered.

  @stable
  ###
  follow = up.mockable (link, options) ->
    return up.render(followOptions(link, options))

  parseRequestOptions = (link, options) ->
    options = u.options(options)
    parser = new up.OptionsParser(options, link) # { fail: false }

    options.url = followURL(link, options)
    options.method = followMethod(link, options)
    parser.json('headers')
    parser.json('params')
    parser.booleanOrString('cache')
    parser.booleanOrString('clearCache')
    parser.boolean('solo')
    parser.string('contentType', attr: ['enctype', 'up-content-type'])

    return options

  ###**
  Parses the [render](/up.render) options that would be used to
  [`follow`](/up.follow) the given link, but does not render.

  \#\#\# Example

  Given a link with some `[up-...]` attributes:

  ```html
  <a href="/foo" up-target=".content" up-layer="new">...</a>
  ```

  We can parse the link's render options like this:

  ```js
  let link = document.querySelector('a[href="/foo"]')
  let options = up.link.followOptions(link)
  // => { url: '/foo', method: 'GET', target: '.content', layer: 'new', ... }
  ```

  @function up.link.followOptions
  @param {Element|jQuery|string} link
    The link to follow.
  @return {Object}
  @stable
  ###
  followOptions = (link, options) ->
    # If passed a selector, up.fragment.get() will prefer a match on the current layer.
    link = up.fragment.get(link)
    options = parseRequestOptions(link, options)

    parser = new up.OptionsParser(options, link, fail: true)

    # Feedback options
    parser.boolean('feedback')

    # Fragment options
    parser.boolean('fail')
    parser.options.origin ?= link
    parser.boolean('navigate', default: true)
    parser.string('confirm')
    parser.string('target')
    parser.booleanOrString('fallback')
    parser.parse(((link, attrName) -> e.callbackAttr(link, attrName, ['request', 'response', 'renderOptions'])), 'onLoaded') # same
    parser.string('content')
    parser.string('fragment')
    parser.string('document')

    # Layer options
    parser.boolean('peel')
    parser.string('layer')
    parser.string('baseLayer')
    parser.json('context')
    parser.string('mode')
    parser.string('align')
    parser.string('position')
    parser.string('class')
    parser.string('size')
    parser.booleanOrString('dismissable')
    parser.parse(up.layer.openCallbackAttr, 'onOpened')
    parser.parse(up.layer.closeCallbackAttr, 'onAccepted')
    parser.parse(up.layer.closeCallbackAttr, 'onDismissed')
    parser.string('acceptEvent')
    parser.string('dismissEvent')
    parser.string('acceptLocation')
    parser.string('dismissLocation')
    parser.booleanOrString('historyVisible')

    # Viewport options
    parser.booleanOrString('focus')
    parser.boolean('saveScroll')
    parser.booleanOrString('scroll')
    parser.boolean('revealTop')
    parser.number('revealMax')
    parser.number('revealPadding')
    parser.number('revealSnap')
    parser.string('scrollBehavior')

    # History options
    # { history } is actually a boolean, but we keep the deprecated string
    # variant which should now be passed as { location }.
    parser.booleanOrString('history')
    parser.booleanOrString('location')
    parser.booleanOrString('title')

    # Motion options
    parser.booleanOrString('animation')
    parser.booleanOrString('transition')
    parser.string('easing')
    parser.number('duration')

    up.migrate.parseFollowOptions?(parser)

    # This is the event that may be prevented to stop the follow.
    # up.form.submit() changes this to be up:form:submit instead.
    # The guardEvent will also be assigned a { renderOptions } property in up.render()
    options.guardEvent ||= up.event.build('up:link:follow', log: 'Following link')

    return options

  ###**
  This event is [emitted](/up.emit) when a link is [followed](/up.follow) through Unpoly.

  The event is emitted on the `<a>` element that is being followed.

  \#\#\# Changing render options

  Listeners may inspect and manipulate [render options](/up.render) for the coming fragment update.

  The code below will open all form-contained links in an overlay, as to not
  lose the user's form data:

  ```js
  up.on('up:link:follow', function(event, link) {
    if (link.closest('form')) {
      event.renderOptions.layer = 'new'
    }
  })
  ```

  @event up:link:follow
  @param {Element} event.target
    The link element that will be followed.
  @param {Object} event.renderOptions
    An object with [render options](/up.render) for the coming fragment update.

    Listeners may inspect and modify these options.
  @param event.preventDefault()
    Event listeners may call this method to prevent the link from being followed.
  @stable
  ###

  ###**
  Preloads the given link.

  When the link is clicked later, the response will already be [cached](/up.cache),
  making the interaction feel instant.

  @function up.link.preload
  @param {string|Element|jQuery} link
    The element or selector whose destination should be preloaded.
  @param {Object} options
    See options for `up.follow()`.
  @return {Promise}
    A promise that will be fulfilled when the request was loaded and cached.

    When preloading is [disabled](/up.link.config#config.preloadEnabled) the promise
    rejects with an `AbortError`.
  @stable
  ###
  preload = (link, options) ->
    # If passed a selector, up.fragment.get() will match in the current layer.
    link = up.fragment.get(link)

    unless shouldPreload()
      return up.error.failed.async('Link preloading is disabled')

    guardEvent = up.event.build('up:link:preload', log: ['Preloading link %o', link])
    return follow(link, u.merge(options, preload: true, { guardEvent }))

  shouldPreload = ->
    setting = config.preloadEnabled

    if setting == 'auto'
      # Since connection.effectiveType might change during a session we need to
      # re-evaluate the value every time.
      return !up.network.shouldReduceRequests()

    return setting

  ###**
  This event is [emitted](/up.emit) before a link is [preloaded](/up.preload).

  @event up:link:preload
  @param {Element} event.target
    The link element that will be preloaded.
  @param event.preventDefault()
    Event listeners may call this method to prevent the link from being preloaded.
  @stable
  ###

  ###**
  Returns the HTTP method that should be used when following the given link.

  Looks at the link's `up-method` or `data-method` attribute.
  Defaults to `"get"`.

  @function up.link.followMethod
  @param link
  @param options.method {string}
  @internal
  ###
  followMethod = (link, options = {}) ->
    u.normalizeMethod(options.method || link.getAttribute('up-method') || link.getAttribute('data-method'))

  followURL = (link, options = {}) ->
    url = options.url || link.getAttribute('href') || link.getAttribute('up-href')

    # Developers sometimes make a <a href="#"> to give a JavaScript interaction standard
    # link behavior (like keyboard navigation or default styles). However, we don't want to
    # consider this  a link with remote content, and rather honor [up-content], [up-document]
    # and [up-fragment] attributes.
    if url != '#'
      return url

  ###**
  Returns whether the given link will be [followed](/up.follow) by Unpoly
  instead of making a full page load.

  By default Unpoly will follow links if the element has
  one of the following attributes:

  - `[up-follow]`
  - `[up-target]`
  - `[up-layer]`
  - `[up-mode]`
  - `[up-transition]`
  - `[up-content]`
  - `[up-fragment]`
  - `[up-document]`

  To make additional elements followable, see `up.link.config.followSelectors`.

  @function up.link.isFollowable
  @param {Element|jQuery|string} link
    The link to check.
  @stable
  ###
  isFollowable = (link) ->
    link = up.fragment.get(link)
    return e.matches(link, fullFollowSelector()) && !isFollowDisabled(link)

  ###**
  Makes sure that the given link will be [followed](/up.follow)
  by Unpoly instead of making a full page load.

  If the link is not already [followable](/up.link.isFollowable), the link
  will receive an `a[up-follow]` attribute.

  @function up.link.makeFollowable
  @param {Element|jQuery|string} link
    The element or selector for the link to make followable.
  @experimental
  ###
  makeFollowable = (link) ->
    unless isFollowable(link)
      link.setAttribute('up-follow', '')

  makeClickable = (link) ->
    if e.matches(link, 'a[href], button')
      return

    e.setMissingAttrs(link, {
      tabindex: '0' # Make them part of the natural tab order
      role: 'link'  # Make screen readers pronounce "link"
    })

    link.addEventListener 'keydown', (event) ->
      if event.key == 'Enter' || event.key == 'Space'
        forkEventAsUpClick(event)

  ###**
  Enables keyboard interaction for elements that should behave like links or buttons.

  The element will be focusable and screen readers will announce it as a link.

  Also see [`up.link.config.clickableSelectors`](/up.link.config#config.clickableSelectors).

  @selector [up-clickable]
  @experimental
  ###
  up.macro(fullClickableSelector, makeClickable)

  shouldFollowEvent = (event, link) ->
    # Users may configure up.link.config.followSelectors.push('a')
    # and then opt out individual links with [up-follow=false].
    if event.defaultPrevented || isFollowDisabled(link)
      return false

    # If user clicked on a child link of $link, or in an <input> within an [up-expand][up-href]
    # we want those other elements handle the click.
    betterTargetSelector = "a, [up-href], #{up.form.fieldSelector()}"
    betterTarget = e.closest(event.target, betterTargetSelector)
    return !betterTarget || betterTarget == link

  isInstant = (linkOrDescendant) ->
    element = e.closest(linkOrDescendant, fullInstantSelector())
    # Allow users to configure up.link.config.instantSelectors.push('a')
    # but opt out individual links with [up-instant=false].
    return element && !isInstantDisabled(element)

  ###**
  Provide an `up:click` event that improves on standard click
  in several ways:

  - It is emitted on mousedown for [up-instant] elements
  - It is not emitted if the element has disappeared (or was overshadowed)
    between mousedown and click. This can happen if mousedown creates a layer
    over the element, or if a mousedown handler removes a handler.

  TODO Docs: Is not emitted for modified clicks

  Stopping an up:click event will also stop the underlying event.

  Also see docs for `up:click`.

  @function up.link.convertClicks
  @param {up.Layer} layer
  @internal
  ###
  convertClicks = (layer) ->
    layer.on 'click', (event, element) ->
      # We never handle events for the right mouse button,
      # or when Shift/CTRL/Meta/ALT is pressed
      unless up.event.isUnmodified(event)
        return

      # (1) Instant links should not have a `click` event.
      #     This would trigger the browsers default follow-behavior and possibly activate JS libs.
      # (2) A11Y: We also need to check whether the [up-instant] behavior did trigger on mousedown.
      #     Keyboard navigation will not necessarily trigger a mousedown event.
      if isInstant(element) && lastMousedownTarget
        up.event.halt(event)

      # In case mousedown has created a layer over the click coordinates,
      # Chrome will emit an event with { target: document.body } on click.
      # Ignore that event and only process if we would still hit the
      # expect layers at the click coordinates.
      else if layer.wasHitByMouseEvent(event) && !didUserDragAway(event)
        forkEventAsUpClick(event)

      # In case the user switches input modes.
      lastMousedownTarget = null

    layer.on 'mousedown', (event, element) ->
      # We never handle events for the right mouse button,
      # or when Shift/CTRL/Meta/ALT is pressed
      unless up.event.isUnmodified(event)
        return

      lastMousedownTarget = event.target

      if isInstant(element)
        # A11Y: Keyboard navigation will not necessarily trigger a mousedown event.
        # We also don't want to listen to the enter key, since some screen readers
        # use the enter key for something else.
        forkEventAsUpClick(event)

  didUserDragAway = (clickEvent) ->
    lastMousedownTarget && lastMousedownTarget != clickEvent.target

  forkEventAsUpClick = (originalEvent) ->
    newEvent = up.event.fork(originalEvent, 'up:click', ['clientX', 'clientY', 'button', up.event.keyModifiers...])
    up.emit(originalEvent.target, newEvent, log: false)

  ###**
  A `click` event that honors the [`[up-instant]`](/a-up-instant) attribute.

  This event is generally emitted when an element is clicked. However, for elements
  with an [`[up-instant]`](/a-up-instant) attribute this event is emitted on `mousedown` instead.

  This is useful to listen to links being activated, without needing to know whether
  a link is `[up-instant]`.

  \#\#\# Example

  Assume we have two links, one of which is `[up-instant]`:

  ```html
  <a href="/one">Link 1</a>
  <a href="/two" up-instant>Link 2</a>
  ```

  The following event listener will be called when *either* link is activated:

  ```js
  document.addEventListener('up:click', function(event) {
    ...
  })
  ```

  \#\#\# Cancelation is forwarded

  If the user cancels an `up:click` event using `event.preventDefault()`,
  the underlying `click` or `mousedown` event will also be canceled.

  \#\#\# Accessibility

  If the user activates an element using their keyboard, the `up:click` event will be emitted
  when the key is pressed even if the element has an `[up-instant]` attribute.

  \#\#\# Only unmodified clicks are considered

  To prevent overriding native browser behavior, the `up:click` is only emitted for unmodified clicks.

  In particular, it is not emitted when the user holds `Shift`, `CTRL` or `Meta` while clicking.
  Neither it is emitted when the user clicks with a secondary mouse button.

  @event up:click
  @param {Element} event.target
    The clicked element.
  @param {Event} event.originalEvent
    The underlying `click` or `mousedown` event.
  @stable
  ###

  ###**
  Returns whether the given link has a [safe](https://www.w3.org/Protocols/rfc2616/rfc2616-sec9.html#sec9.1.1)
  HTTP method like `GET`.

  @function up.link.isSafe
  @param {Element} link
  @return {boolean}
  @stable
  ###
  isSafe = (link) ->
    method = followMethod(link)
    up.network.isSafeMethod(method)

  ###**
  [Follows](/up.follow) this link with JavaScript and updates a fragment with the server response.

  Following a link is considered [navigation](/navigation) by default.

  \#\#\# Example

  This will update the fragment `<div class="content">` with the same element
  fetched from `/posts/5`:

  ```html
  <a href="/posts/5" up-follow up-target=".content">Read post</a>
  ```

  If no `[up-target]` attribute is set, the [main target](/up-main) is updated.

  \#\#\# Advanced fragment changes

  See [fragment placement](/fragment-placement) for advanced use cases
  like updating multiple fragments or appending content to an existing element.

  \#\#\# Short notation

  You may omit the `[up-follow]` attribute if the link has one of the following attributes:

  - `[up-target]`
  - `[up-layer]`
  - `[up-transition]`
  - `[up-content]`
  - `[up-fragment]`
  - `[up-document]`

  Such a link will still be followed through Unpoly.

  \#\#\# Following all links automatically

  You can configure Unpoly to follow *all* links on a page without requiring an `[up-follow]` attribute.

  See [Handling all links and forms](/handling-everything).

  @selector a[up-follow]

  @param [href]
    The URL to fetch from the server.

    Instead of making a server request, you may also pass an existing HTML string as
    `[up-document]` or `[up-content]` attribute.

  @param [up-target]
    The CSS selector to update.

    If omitted a [main target](/up-main) will be rendered.

  @param [up-fallback]
    Specifies behavior if the [target selector](/up.render#options.target) is missing from the current page or the server response.

    If set to a CSS selector, Unpoly will attempt to replace that selector instead.

    If set to `true` Unpoly will attempt to replace a [main target](/up-main) instead.

    If set to `false` Unpoly will immediately reject the render promise.

  @param [up-navigate='true']
    Whether this fragment update is considered [navigation](/navigation).

  @param [up-method='get']
    The HTTP method to use for the request.

    Common values are `get`, `post`, `put`, `patch` and `delete`. The value is case insensitive.

    The HTTP method may also be passed as an `[data-method]` attribute.

    By default, methods other than `get` or `post` will be converted into a `post` request, and carry
    their original method as a configurable [`_method` parameter](/up.protocol.config#config.methodParam).

  @param [up-params]
    A JSON object with additional [parameters](/up.Params) that should be sent as the request's
    [query string](https://en.wikipedia.org/wiki/Query_string) or payload.

    When making a `GET` request to a URL with a query string, the given `{ params }` will be added
    to the query parameters.

  @param [up-headers]
    A JSON object with additional request headers.

    Note that Unpoly will by default send a number of custom request headers.
    E.g. the `X-Up-Target` header includes the targeted CSS selector.
    See `up.protocol` and `up.network.config.metaKeys` for details.

  @param [up-fragment]
    A string of HTML comprising *only* the new fragment. No server request will be sent.

    The `[up-target]` selector will be derived from the root element in the given
    HTML:

    ```html
    <!-- This will update .foo -->
    <a up-fragment='&lt;div class=".foo"&gt;inner&lt;/div&gt;'>Click me</a>
    ```

    If your HTML string contains other fragments that will not be rendered, use
    the `[up-document]` attribute instead.

    If your HTML string comprises only the new fragment's [inner HTML](https://developer.mozilla.org/en-US/docs/Web/API/Element/innerHTML),
    consider the `[up-content]` attribute instead.

  @param [up-document]
    A string of HTML containing the new fragment.

    The string may contain other HTML, but only the element matching the
    `[up-target]` selector will be extracted and placed into the page.
    Other elements will be discarded.

    If your HTML string comprises only the new fragment, consider the `[up-fragment]` attribute
    instead. With `[up-fragment]` you don't need to pass a `[up-target]`, since
    Unpoly can derive it from the root element in the given HTML.

    If your HTML string comprises only the new fragment's [inner HTML](https://developer.mozilla.org/en-US/docs/Web/API/Element/innerHTML),
    consider the `[up-content]` attribute.

  @param [up-fail='auto']
    How to render a server response with an error code.

    Any HTTP status code other than 2xx is considered an error code.

    See [handling server errors](/server-errors) for details.

  @param [up-history]
    Whether the browser URL and window title will be updated.

    If set to `true`, the history will always be updated, using the title and URL from
    the server response, or from given `[up-title]` and `[up-location]` attributes.

    If set to `auto` history will be updated if the `[up-target]` matches
    a selector in `up.fragment.config.autoHistoryTargets`. By default this contains all
    [main targets](/up-main).

    If set to `false`, the history will remain unchanged.

    [Overlays](/up.layer) will only change the browser URL and window title if the overlay
    has [visible history](/up.layer.historyVisible), even when `[up-history=true]` is set.

  @param [up-title]
    An explicit document title to use after rendering.

    By default the title is extracted from the response's `<title>` tag.
    You may also set `[up-title=false]` to explicitly prevent the title from being updated.

    Note that the browser's window title will only be updated it you also
    set an `[up-history]` attribute.

  @param [up-location]
    An explicit URL to use after rendering.

    By default Unpoly will use the link's `[href]` or the final URL after the server redirected.
    You may also set `[up-location=false]` to explicitly prevent the URL from being updated.

    Note that the browser's URL will only be updated it you also
    set an `[up-history]` attribute.

  @param [up-transition]
    The name of an [transition](/up.motion) to morph between the old and few fragment.

    If you are [prepending or appending content](/fragment-placement#appending-or-prepending-content),
    use the `[up-animation]` attribute instead.

  @param [up-animation]
    The name of an [animation](/up.motion) to reveal a new fragment when
    [prepending or appending content](/fragment-placement#appending-or-prepending-content).

    If you are replacing content (the default), use the `[up-transition]` attribute instead.

  @param [up-duration]
    The duration of the transition or animation (in millisconds).

  @param [up-easing]
    The timing function that accelerates the transition or animation.

    See [W3C documentation](http://www.w3.org/TR/css3-transitions/#transition-timing-function)
    for a list of available timing functions.

  @param [up-cache]
    Whether to read from and write to the [cache](/up.cache).

    With `[up-cache=true]` Unpoly will try to re-use a cached response before connecting
    to the network. If no cached response exists, Unpoly will make a request and cache
    the server response.

    With `[up-cache=auto]` Unpoly will use the cache only if `up.network.config.autoCache`
    returns `true` for the request.

    Also see [`up.request({ cache })`](/up.request#options.cache).

  @param [up-clear-cache]
    Whether existing [cache](/up.cache) entries will be cleared with this request.

    By default a non-GET request will clear the entire cache.
    You may also pass a [URL pattern](/url-patterns) to only clear matching requests.

    Also see [`up.request({ clearCache })`](/up.request#options.clearCache) and `up.network.config.clearCache`.

  @param [up-layer='origin current']
    The [layer](/up.layer) in which to match and render the fragment.

    See [layer option](/layer-option) for a list of allowed values.

    To [open the fragment in a new overlay](/opening-overlays), pass `[up-layer=new]`.
    In this case attributes for `a[up-layer=new]` may also be used.

  @param [up-peel]
    Whether to close overlays obstructing the updated layer when the fragment is updated.

    This is only relevant when updating a layer that is not the [frontmost layer](/up.layer.front).

  @param [up-context]
    A JSON object that will be merged into the [context](/context)
    of the current layer once the fragment is rendered.

  @param [up-keep='true']
    Whether [`[up-keep]`](/up-keep) elements will be preserved in the updated fragment.

  @param [up-hungry='true']
    Whether [`[up-hungry]`](/up-hungry) elements outside the updated fragment will also be updated.

  @param [up-scroll]
    How to scroll after the new fragment was rendered.

    See [scroll option](/scroll-option) for a list of allowed values.

  @param [up-save-scroll]
    Whether to save scroll positions before updating the fragment.

    Saved scroll positions can later be restored with [`[up-scroll=restore]`](/scroll-option#restoring-scroll-options).

  @param [up-focus]
    What to focus after the new fragment was rendered.

    See [focus option](/focus-option) for a list of allowed values.

  @param [up-confirm]
    A message the user needs to confirm before fragments are updated.

    The message will be shown as a [native browser prompt](https://developer.mozilla.org/en-US/docs/Web/API/Window/prompt).

    If the user does not confirm the render promise will reject and no fragments will be updated.

  @param [up-feedback]
    Whether to give the link an `.up-active` class
    while loading and rendering content.

  @param [up-on-loaded]
    A JavaScript snippet that is called when when the server responds with new HTML,
    but before the HTML is rendered.

    The callback argument is a preventable `up:fragment:loaded` event.

  @param [up-on-finished]
    A JavaScript snippet that is called when all animations have concluded and
    elements were removed from the DOM tree.

  @stable
  ###
  up.on 'up:click', fullFollowSelector, (event, link) ->
    if shouldFollowEvent(event, link)
      up.event.halt(event)
      up.log.muteUncriticalRejection follow(link)

  ###**
  Follows this link on `mousedown` instead of `click`.

  This will save precious milliseconds that otherwise spent
  on waiting for the user to release the mouse button. Since an
  AJAX request will be triggered right way, the interaction will
  appear faster.

  Note that using `[up-instant]` will prevent a user from canceling a
  click by moving the mouse away from the link. However, for
  navigation actions this isn't needed. E.g. popular operation
  systems switch tabs on `mousedown` instead of `click`.

  \#\#\# Example

      <a href="/users" up-follow up-instant>User list</a>

  \#\#\# Accessibility

  If the user activates an element using their keyboard, the `up:click` event will be emitted
  on `click`, even if the element has an `[up-instant]` attribute.

  @selector a[up-instant]
  @stable
  ###

  ###**
  Add an `[up-expand]` attribute to any element to enlarge the click area of a
  descendant link.

  `[up-expand]` honors all the Unppoly attributes in expanded links, like
  `a[up-target]`, `a[up-instant]` or `a[up-preload]`.
  It also expands links that open [modals](/up.modal) or [popups](/up.popup).

  \#\#\# Example

      <div class="notification" up-expand>
        Record was saved!
        <a href="/records">Close</a>
      </div>

  In the example above, clicking anywhere within `.notification` element
  would [follow](/up.follow) the *Close* link.

  \#\#\# Elements with multiple contained links

  If a container contains more than one link, you can set the value of the
  `up-expand` attribute to a CSS selector to define which link should be expanded:

      <div class="notification" up-expand=".close">
        Record was saved!
        <a class="details" href="/records/5">Details</a>
        <a class="close" href="/records">Close</a>
      </div>

  \#\#\# Limitations

  `[up-expand]` has some limitations for advanced browser users:

  - Users won't be able to right-click the expanded area to open a context menu
  - Users won't be able to `CTRL`+click the expanded area to open a new tab

  To overcome these limitations, consider nesting the entire clickable area in an actual `<a>` tag.
  [It's OK to put block elements inside an anchor tag](https://makandracards.com/makandra/43549-it-s-ok-to-put-block-elements-inside-an-a-tag).

  @selector [up-expand]
  @param [up-expand]
    A CSS selector that defines which containing link should be expanded.

    If omitted, the first link in this element will be expanded.
  @stable
  ###
  up.macro '[up-expand]', (area) ->
    selector = area.getAttribute('up-expand') || 'a, [up-href]'

    if childLink = e.get(area, selector)
      areaAttrs = e.upAttrs(childLink)
      areaAttrs['up-href'] ||= childLink.getAttribute('href')
      e.setMissingAttrs(area, areaAttrs)
      makeFollowable(area)

  ###**
  Preloads this link when the user hovers over it.

  When the link is clicked later the response will already be cached,
  making the interaction feel instant.

  @selector a[up-preload]
  @param [up-delay]
    The number of milliseconds to wait between hovering
    and preloading. Increasing this will lower the load in your server,
    but will also make the interaction feel less instant.

    Defaults to `up.link.config.preloadDelay`.
  @stable
  ###
  up.compiler fullPreloadSelector, (link) ->
    unless isPreloadDisabled(link)
      return linkPreloader.observeLink(link)

  up.on 'up:framework:reset', reset

  follow: follow
  followOptions: followOptions
  preload: preload
  makeFollowable: makeFollowable
  makeClickable: makeClickable
  isSafe: isSafe
  isFollowable: isFollowable
  shouldFollowEvent: shouldFollowEvent
  followMethod: followMethod
  convertClicks: convertClicks
  config: config
  combineFollowableSelectors: combineFollowableSelectors

up.follow = up.link.follow
