{-
   Copyright 2014 Jason R Briggs

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

-}

module Text.Proton.Xml (
Element(..),
Attribute(..),
ElementType(..),
RenderCallbackFn(..),
containsAttribute,
copyElement,
copyElements,
findAttribute,
getAttributes,
getChildren,
parseXmlFile,
parseAttributes,
render,
render'
) where


import qualified Data.Map as Map

import Text.Proton.XmlTypes
import Text.Proton.XmlInternal


containsAttribute :: String -> [Attribute] -> Bool
containsAttribute _ [] = False
containsAttribute name (x:xs) = do
    let aname = attname x
    (aname == name) || containsAttribute name xs


copyElement :: Element -> Element
copyElement (Element elemtype s atts xs) = Element elemtype s atts (copyElements xs)


copyElements :: [Element] -> [Element]
copyElements = map copyElement


findAttribute :: String -> [Attribute] -> Attribute
findAttribute _ [] = NoAttribute
findAttribute name (x:xs) = do
    let aname = attname x
    if aname == name then x
    else findAttribute name xs


getChildren :: Element -> [Element]
getChildren (Element _ _ _ xs) = xs


getAttributes :: Element -> [Attribute]
getAttributes (Element _ _ atts _) = atts


-- parse a string into a list of attributes
parseAttributes       :: String -> [Attribute]
parseAttributes ""    = []
parseAttributes ">"   = []
parseAttributes " />" = []
parseAttributes "/>"  = []
parseAttributes s     = do
    let news = dropWhile (matches " \"") s
    let (name, maybeValue) = splitOn '=' news
    let (value, rest) = splitUntilClose maybeValue
    Attribute name value 1 : (if rest /= "" 
                                then parseAttributes (tail rest) 
                                else [])


-- return the tag name, and then the remaining content of the element
parseTag   :: String -> (String, String)
parseTag s = do
    let (_, remainder) = span (matches "</") s
    break (matches " >/") remainder


-- internal xml parser code
parse    :: [String] -> ([Element], [String])
parse [] = ([], [])
parse (x:xs) = do
    let first = head x
    let sec = head (tail x)
    let seclst = last (init x)
    let lst = last x
    
    case (first, sec, seclst, lst) of
        ('<', '?', _, _)   -> do
            let (parsed, remaining) = parse xs
            (Element Raw x [] [] : parsed, remaining)
        ('<', '!', _, _)   -> do
            let (parsed, remaining) = parse xs
            (Element Raw x [] [] : parsed, remaining)
        ('<', _, '/', '>') -> do
            let (tag, tagcontent) = parseTag x
            let attributes = parseAttributes tagcontent
            let (parsed, remaining) = parse xs
            (Element Closed tag attributes [] : parsed, remaining)
        ('<', '/', _, '>') -> ([], xs)
        ('<', _, _, '>')   -> do
            let (tag, tagcontent) = parseTag x
            let attributes = parseAttributes tagcontent
            let (children, siblings) = parse xs
            let (parsed, remaining) = parse siblings
            (Element Open tag attributes children : parsed, remaining)
        (_, _, _, _)       -> do
            let (parsed, remaining) = parse xs
            (Element Raw x [] [] : parsed, remaining)


parseXmlFile       :: String -> IO Element
parseXmlFile fname = do    
   file <- readFile fname
   let sp = splitText file
   let (parsed, _) = parse sp
   return (Element Root "" [] parsed)


getData :: (RenderCallbackFn (String, [Attribute], [Element]) b) -> (String, [Attribute], [Element])
getData (RenderCallbackFn a _) = do
    let (tag, atts, xs) = a
    (tag, atts, xs)


getFn :: RenderCallbackFn a b -> b -> RenderCallbackFn a b
getFn (RenderCallbackFn _ b) = b


-- the "no op" function for basic rendering (i.e. render without callback)
renderNoop :: (String, [Attribute], [Element]) -> RenderCallbackFn (String, [Attribute], [Element]) (String, [Attribute], [Element])
renderNoop (s, atts, xs) = RenderCallbackFn (s, atts, xs) renderNoop


render   :: Element -> String
render e = render' e renderNoop


render' :: Element -> ((String, [Attribute], [Element]) -> RenderCallbackFn (String, [Attribute], [Element]) (String, [Attribute], [Element])) -> String
render' e fn = do
    let (newe, _) = preprocessElement e Map.empty
    renderElement newe fn


incrementOccurrences :: [Attribute] -> Map.Map String Integer -> ([Attribute], Map.Map String Integer)
incrementOccurrences [] occurrences     = ([], occurrences)
incrementOccurrences (a:as) occurrences = do
    let (Attribute name val _) = a

    if name == "eid" || name == "aid"
        then do
            let key = name ++ "/" ++ val
            let count = Map.findWithDefault 0 key occurrences + 1
            let newoccurrences = Map.insert key count occurrences
            let (newatts, newoccurrences2) = incrementOccurrences as newoccurrences
            (Attribute name val count : newatts, newoccurrences2)
        else do
            let (newatts, newoccurrences) = incrementOccurrences as occurrences
            (a : newatts, newoccurrences)


preprocessElement :: Element -> Map.Map String Integer -> (Element, Map.Map String Integer)
preprocessElement e occurrences  = do
    let (Element elemtype s atts xs) = e
    let (newatts, newoccurrences) = incrementOccurrences atts occurrences
    let (newxs, newoccurrences2) = preprocessElement' xs newoccurrences
    (Element elemtype s newatts newxs, newoccurrences2)


preprocessElement' :: [Element] -> Map.Map String Integer -> ([Element], Map.Map String Integer)
preprocessElement' [] occurrences = ([], occurrences)
preprocessElement' (e:es) occurrences = do
    let (newe, newoccurrences) = preprocessElement e occurrences
    let (newes, newoccurrences2) = preprocessElement' es newoccurrences
    (newe : newes, newoccurrences2)
    

renderElement :: Element -> ((String, [Attribute], [Element]) -> RenderCallbackFn (String, [Attribute], [Element]) (String, [Attribute], [Element])) -> String
renderElement (Element elemtype s atts xs) fn =
    case elemtype of
        (Raw) -> s
        (Closed) -> renderClosed s atts fn
        (Open) -> renderOpen s atts xs fn
        (Root) -> renderList xs fn


renderClosed :: String -> [Attribute] -> ((String, [Attribute], [Element]) -> RenderCallbackFn (String, [Attribute], [Element]) (String, [Attribute], [Element])) -> String
renderClosed s atts fn = do
    let fnres = fn (s, atts, [Element Raw "" [] []])
    let (newtag, newatts, _) = getData fnres
    "<" ++ newtag ++ renderAttributeList newatts ++ " />"


renderOpen :: String -> [Attribute] -> [Element] -> ((String, [Attribute], [Element]) -> RenderCallbackFn (String, [Attribute], [Element]) (String, [Attribute], [Element])) -> String
renderOpen s atts xs fn = do
    let fnres = fn (s, atts, xs)
    let (newtag, newatts, newxs) = getData fnres
    let newfn = getFn fnres
    "<" ++ newtag ++ renderAttributeList newatts ++ ">" ++ renderList newxs newfn ++ "</" ++ newtag ++ ">"


renderList :: [Element] -> ((String, [Attribute], [Element]) -> RenderCallbackFn (String, [Attribute], [Element]) (String, [Attribute], [Element])) -> String
renderList xs fn = foldr (\ x -> (++) (renderElement x fn)) "" xs


renderAttribute :: Attribute -> String
renderAttribute NoAttribute = ""
renderAttribute (Attribute name val _) =
    if name == "rid" || name == "eid" || name == "aid" 
        then ""
        else " " ++ name ++ "=\"" ++ val ++ "\""


renderAttributeList    :: [Attribute] -> String
renderAttributeList = foldr ((++) . renderAttribute) ""
