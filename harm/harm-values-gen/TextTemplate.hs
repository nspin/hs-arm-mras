module Main (main) where

import Extract
import Data.Monoid
import Data.Foldable
import Text.Show

main :: IO ()
main = puts . unliness $ map f encodingGroups
  where
    f (tplt, grp) =
          showString "# \"" . showString tplt . showString "\"\n"
        . showString "type: \n"
        . showString "fields: \n"
        . unliness (map el grp)
    el (mnem, encid, file) =
          showString "- "
        . showString mnem
        . showString (replicate (10 - length mnem) ' ')
        . showString file

unliness :: [ShowS] -> ShowS
unliness = concats . map (. showChar '\n')

concats :: [ShowS] -> ShowS
concats = appEndo . foldMap Endo

puts :: ShowS -> IO ()
puts s = putStr (s "")