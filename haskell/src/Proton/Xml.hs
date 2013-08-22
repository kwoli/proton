module Proton.Xml (
Element(..),
Attribute(..),
ElementType(..),
RenderCallbackFn(..),
findAttributeValue,
getAttributes,
getChildren,
parseXmlFile,
render,
render'
) where

import Data.String.Utils
import Data.List (intercalate)
import Text.Regex


data Attribute = Attribute { attname :: String, attvalue :: String }
                 deriving (Show)

data ElementType = Root
                 | Raw
                 | Open
                 | Closed
                 deriving (Show)

data Element = Element ElementType String [Attribute] [Element]
               deriving (Show)


data RenderCallbackFn a b = RenderCallbackFn a (b -> RenderCallbackFn a b)


-- does the char in arg #2 match any of the chars in arg #1?
matches :: [Char] -> Char -> Bool
matches [] c = False
matches (x:xs) c = do
   if x == c then True
   else matches xs c


isWhitespace char = matches [' ','\n', '\t', '\r'] char


-- same as span, except the first list is loaded with elements up-to-and-including the match
spanUntil chk [] = ([], [])
spanUntil chk (x:xs) =
   if chk x then ([ x ], xs)
   else do
       let (hd, tl) = spanUntil chk xs
       ([x] ++ hd, tl)


splitOn         :: Char -> String -> (String, String)
splitOn char s = do
    let (splitA, splitB) = span (/=char) s
    if (length splitB) > 0 then (splitA, tail splitB)
    else (splitA, splitB)


-- split used for XML files, to ensure an xml tag element is a distinct member of the list returned
splitText :: String -> [String]
splitText [] = []
splitText (x:xs) = 
    if x == '<' then do
        let (first, rest) = spanUntil (=='>') xs
        [x : first] ++ splitText rest
    else do
        if isWhitespace x then do
            let (first, rest) = span (isWhitespace) xs
            [x : first] ++ splitText rest
        else do
            let (first, rest) = span (/='<') xs
            [x : first] ++ splitText rest


findAttributeValue :: String -> [Attribute] -> Maybe String
findAttributeValue name [] = Nothing
findAttributeValue name (x:xs) = do
    let aname = attname x
    let avalue = attvalue x
    if aname == name then Just avalue
    else findAttributeValue name xs


getChildren :: Element -> [Element]
getChildren (Element elemtype s atts xs) = xs


getAttributes :: Element -> [Attribute]
getAttributes (Element elemtype s atts xs) = atts


-- todo: fix escaped double quote in attr value
parseAttributes      :: String -> [Attribute]
parseAttributes ""   = []
parseAttributes ">"  = []
parseAttributes " />" = []
parseAttributes "/>" = []
parseAttributes s    = do
    let news = dropWhile (matches [' ', '"']) s
    let (name, maybeValue) = splitOn '=' news
    let (value, rest) = span (not . matches ['"']) $ dropWhile (matches ['=', '"', '>']) maybeValue
    [Attribute name value] ++ if rest /= "" then parseAttributes (tail rest) else []


-- return the tag name, and then the remaining content of the element
parseTag :: String -> (String, String)
parseTag s = do
    let (_, remainder) = span (matches ['<','/']) s
    span (not . matches [' ','>', '/']) remainder


-- internal xml parser code
parse :: [String] -> ([Element], [String])
parse [] = ([], [])
parse (x:xs) = do
    let first = head x
    let sec = head (tail x)
    let seclst = last (init x)
    let lst = last x
    
    case (first, sec, seclst, lst) of
        ('<', '?', _, _)   -> do
            let (parsed, remaining) = parse xs
            ([Element Raw x [] []] ++ parsed, remaining)
        ('<', '!', _, _)   -> do
            let (parsed, remaining) = parse xs
            ([Element Raw x [] []] ++ parsed, remaining)
        ('<', _, '/', '>') -> do
            let (tag, tagcontent) = parseTag x
            let attributes = parseAttributes tagcontent
            let (parsed, remaining) = parse xs
            ([Element Closed tag attributes []] ++ parsed, remaining)
        ('<', '/', _, '>') -> ([], xs)
        ('<', _, _, '>')   -> do
            let (tag, tagcontent) = parseTag x
            let attributes = parseAttributes tagcontent
            let (children, siblings) = parse xs
            let (parsed, remaining) = parse siblings
            ([Element Open tag attributes children] ++ parsed, remaining)
        (_, _, _, _)       -> do
            let (parsed, remaining) = parse xs
            ([Element Raw x [] []] ++ parsed, remaining)


parseXmlFile :: String -> IO Element
parseXmlFile fname = do    
   file <- readFile fname
   let sp = splitText file
   let (parsed, _) = parse sp
   return (Element Root "" [] parsed)


getData (RenderCallbackFn a b) = do
    let (tag, atts, xs) = a
    (tag, atts, xs)


getFn (RenderCallbackFn a b) = b


--renderNoop :: String -> [Attribute] -> [Element] -> (String, [Attribute], [Element])
renderNoop (s, atts, xs) = RenderCallbackFn (s, atts, xs) renderNoop


render :: Element -> String
render el = render' el renderNoop


render' (Element elemtype s atts xs) fn = do
    case elemtype of
        (Raw) -> s
        (Closed) -> renderClosed s atts fn
        (Open) -> renderOpen s atts xs fn
        (Root) -> renderList xs fn


--renderClosed :: RenderCallbackFn a b -> String
renderClosed s atts fn = do
    let fnres = fn (s, atts, [(Element Raw "" [] [])])
    let (newtag, newatts, _) = getData fnres
    "<" ++ newtag ++ (renderAttributeList newatts) ++ " />"


--renderOpen :: String -> [Attribute] -> [Element] -> (String -> [Attribute] -> [Element] -> (String, [Attribute], [Element])) -> String
renderOpen s atts xs fn = do
    let fnres = fn (s, atts, xs)
    let (newtag, newatts, newxs) = getData fnres
    let newfn = getFn fnres
    "<" ++ newtag ++ (renderAttributeList newatts) ++ ">" ++ (renderList newxs newfn) ++ "</" ++ newtag ++ ">"


--renderList :: [Element] -> (String -> [Attribute] -> [Element] -> (String, [Attribute], [Element])) -> String
renderList [] fn     = ""
renderList (x:xs) fn = do
    (render' x fn) ++ (intercalate "" (map renderInternal xs))
    where renderInternal x = render' x fn


renderAttribute :: Attribute -> String
renderAttribute (Attribute name val) = " " ++ name ++ "=\"" ++ val ++ "\""


renderAttributeList :: [Attribute] -> String
renderAttributeList [] = ""
renderAttributeList (x:xs) = renderAttribute x ++ (intercalate "" (map renderAttribute xs))
