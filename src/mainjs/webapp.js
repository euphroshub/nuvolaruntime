/*
 * Copyright 2014 Jiří Janoušek <janousek.jiri@gmail.com>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met: 
 * 
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer. 
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution. 
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

require("prototype");
require("signals");
require("core");

var WebApp = $prototype(null, SignalsMixin);
WebApp.LAST_URI = "web_app.last_uri";

WebApp.$init = function()
{
	this.meta = Nuvola.meta;
	var allowedURI = this.meta.allowed_uri;
	this.allowedURI = allowedURI ? new RegExp(allowedURI) : null;
	Nuvola.core.connect("HomePageRequest", this);
	Nuvola.core.connect("LastPageRequest", this);
	Nuvola.core.connect("NavigationRequest", this);
	Nuvola.core.connect("UriChanged", this);
	Nuvola.core.connect("InitAppRunner", this);
	Nuvola.core.connect("InitWebWorker", this);
}

WebApp.start = function()
{
	Nuvola.webApp = $object(this);
}

WebApp._onHomePageRequest = function(object, result)
{
	result.url = this.meta.home_url;
}

WebApp._onLastPageRequest = function(object, result)
{
	result.url = Nuvola.config.get(this.LAST_URI) || null;
}

WebApp._onNavigationRequest = function(object, request)
{
	request.approved = this.allowedURI ? true : this.allowedURI.test(request.url);
}

WebApp._onUriChanged = function(object, uri)
{
	Nuvola.config.set(this.LAST_URI, uri);
}

WebApp._onInitAppRunner = function(emitter, values, entries)
{
}

/**
 * @method WebAppPrototype.onInitWebWorker
 * 
 * Handler for Core::InitWebWorker signal. Override this method to integrate the web page.
 * 
 * ```
 * WebApp._onInitWebWorker = function(emitter)
 * {
 *     Nuvola.WebApp._onInitWebWorker.call(this);
 *     // one of these:
 *     document.addEventListener("DOMContentLoaded", this._onPageReady.bind(this));
 *     window.addEventListener("load", this._onPageReady.bind(this));
 * }
 * 
 * WebApp._onPageReady = function(event)
 * {
 *     ...
 * }
 * ```
 */
WebApp._onInitWebWorker = function(emitter)
{
}

// export public fields
Nuvola.WebApp = WebApp;
Nuvola.$WebApp = function()
{
	if (this !== Nuvola)
		throw new Error("Nuvola.$WebApp has been called incorrectly. Use `var WebApp = Nuvola.$WebApp();` idiom.");
	
	return $prototype(WebApp);
}

