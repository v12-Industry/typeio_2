{-# LANGUAGE OverloadedStrings #-}

module Common.Web.Elements where

import Lucid.Base

circle_ :: Term arg result => arg -> result
circle_ = term "circle"

defs_ :: Term arg result => arg -> result
defs_ = term "defs"

path_ :: Term arg result => arg -> result
path_ = term "path"

rect_ :: Term arg result => arg -> result
rect_ = term "rect"

g_ :: Term arg result => arg -> result
g_ = term "g"

line_ :: Term arg result => arg -> result
line_ = term "line"

marker_ :: Term arg result => arg -> result
marker_ = term "marker"

text_ :: Term arg result => arg -> result
text_ = term "text"

tspan_ :: Term arg result => arg -> result
tspan_ = term "tspan"
