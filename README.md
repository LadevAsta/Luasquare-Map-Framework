# Luasquare RBMK
#### A Lua Map Framework for building a semi-realistic simulated modular RBMK-style reactor in Garry's Mod Map.

This is meant to be used by Crazy Gmod Mappers who wants to make a nuclear reactor map where casual players will have nightmare in it.

Core design heavily inspired by the same reactor in a Minecraft mod HBM Nuclear Tech with it's signature 4-direction flux propagation.
...and with a lot of added bloats which made it a lot more complicated for whatever reason.
It is not 100% the same, as I never has looked that deep into that mod's code to see how it actually simulates the reactor.
So I decided to made it all up while taking more inspiration and concepts from many other games about nuclear power plants as well as adding something entirely fictional of my own.

The framework (at the earliest stage) are mostly vibecoded for logics to aid with the rather complicated and lengthy development (and I want sleep).
It is not exactly straightforward to use this in Hammer either. As you'll require the excessive use of lua_run and it's RunPassedCode input!

I started building this because one day I scoured through the gmod workshop looking for some nuclear reactor map. I found one and it was really good, then something happened and I thought it'd be cool if I can make an in-map skin-based 7-segment display that can display any value it is given using Lua Addon as it's driver(at least in singleplayer)...
Then somehow this ENTIRE project started ALL because of that skin-based pesudo-7-segment display.

Why "Luasquare RBMK"? one, Because it's all Lua. two, it was originally "Lithosquare RBMK" but that name is taken and also doesn't quite fit for what this thing is!
