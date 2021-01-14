u = up.util
$ = jQuery

describe 'up.Request', ->

  describe 'constructor', ->

    it 'force-enables caching when preloading', ->
      request = new up.Request(url: '/foo', preload: true, cache: false)
      expect(request.cache).toBe(true)

  describe '#url', ->

    it 'returns the given URL', ->
      request = new up.Request(url: 'http://host.com/foo')
      expect(request.url).toEqual('http://host.com/foo')

    it 'does not include a hash anchor of the constructed URL', ->
      request = new up.Request(url: 'http://host.com/foo#hash')
      expect(request.url).toEqual('http://host.com/foo')

    it "merges { params } for HTTP methods that don't allow a payload", ->
      request = new up.Request(url: 'http://host.com/foo?urlKey=urlValue', params: { paramsKey: 'paramsValue' }, method: 'get')
      expect(request.url).toEqual('http://host.com/foo?urlKey=urlValue&paramsKey=paramsValue')

    it 'keeps query params in the URL for HTTP methods that allow a payload', ->
      request = new up.Request(url: 'http://host.com/foo?key=value', method: 'post')
      expect(request.url).toEqual('http://host.com/foo?key=value')
      expect(request.params).toBeBlank()

  describe '#followState', ->

    it 'resolves this request when the given source request is resolved'

    it 'rejects this request when the given source request is rejected'

    it 'aborts this request when the given source request is aborted', ->
      sourceRequest = new up.Request(url: '/foo')
      followingRequest = new up.Request(url: '/foo')
      followingRequest.followState(sourceRequest)

      expect(sourceRequest.state).toEqual('new')
      expect(followingRequest.state).toEqual('new')

      sourceRequest.abort()

      expect(sourceRequest.state).toEqual('aborted')
      expect(followingRequest.state).toEqual('aborted')

  describe '#testURL', ->

    it "returns true if the given URL pattern matches this request's URL", ->
      request = new up.Request(url: '/foo/123')
      expect(request.testURL('/foo/*')).toBe(true)

    it "returns false if the given URL pattern does not match this request's URL", ->
      request = new up.Request(url: '/foo/123')
      expect(request.testURL('/bar/*')).toBe(false)

  describe '#method', ->

    it 'defaults to "GET"', ->
      request = new up.Request(url: 'http://host.com/foo')
      expect(request.method).toEqual('GET')

  describe '#hash', ->

    it 'returns the hash anchor from the constructed URL', ->
      request = new up.Request(url: 'http://host.com/foo#hash')
      expect(request.hash).toEqual('#hash')

    it 'returns undefined if the constructed URL had no hash anchor', ->
      request = new up.Request(url: 'http://host.com/foo')
      expect(request.hash).toBeUndefined()

  describe '#params', ->

    it 'returns the constructed params for HTTP methods that allow a payload', ->
      params = { key: 'value' }
      request = new up.Request(url: 'http://host.com/foo', params: params, method: 'post')
      expect(request.params).toEqual(new up.Params(params))

    it "returns a blank up.Params object for HTTP methods that don't allow a payload", ->
      request = new up.Request(url: 'http://host.com/foo', params: { key: 'value' }, method: 'get')
      expect(request.params).toBeBlank()
