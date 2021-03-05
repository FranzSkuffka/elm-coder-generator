module Types exposing (..)


type Type
    = TypeArray Type
    | TypeBool
    | TypeDict ( Type, Type )
    | TypeError String --parse error
    | TypeExtendedRecord (List TypeDef) --record defined using an extensible one
    | TypeExtensible (List TypeDef) --extensible record
    | TypeFloat
    | TypeCustom String (List Type) --type not core and not defined in the input
    | TypeInt
    | TypeList Type
    | TypeMaybe Type
    | TypeResult Type Type
    | TypeOpaque ( String, List Type )
    | TypeRecord (List TypeDef)
    | TypeString
    | TypeTuple (List Type)
    | TypeUnion (List ( String, List Type ))
    | TypeParameter String

--options for decoding large record types
type ExtraPackage
    = Extra  --Json.Decode.Extra
    | Pipeline --Json.Decode.Pipeline

type alias RawType =
    { name : String
    , def : String
    , extensible : Bool
    }

type alias TypeDef =
    { name : String
    , theType : Type
    }


simpleType this =
    case this of
        TypeBool ->
            True

        TypeFloat ->
            True

        TypeInt ->
            True

        TypeString ->
            True

        _ ->
            False


coreType : Type -> Bool
coreType this =
    case this of
        TypeArray a ->
            simpleType a

        TypeList a ->
            simpleType a

        TypeMaybe a ->
            simpleType a

        _ ->
            simpleType this


coreTypeForEncoding : Type -> Bool
coreTypeForEncoding this =
    case this of
        TypeMaybe _ ->
            False

        _ ->
            coreType this

isEmptyRecord : TypeDef -> Bool
isEmptyRecord this =
    case this.theType of
        TypeRecord [] ->
            True
        
        _ ->
            False

isNonemptyExtended : TypeDef -> Bool
isNonemptyExtended this =
    case this.theType of
        TypeExtendedRecord [] ->
            False
            
        TypeExtendedRecord _ ->
            True    
            
        _ ->
            False


isExtensible : TypeDef -> Bool
isExtensible this =
    case this.theType of
        TypeExtensible _ ->
            True

        _ ->
            False


isRecord : TypeDef -> Bool
isRecord this =
    case this.theType of
        TypeRecord _ ->
            True

        _ ->
            False

getParameters : Type -> List String
getParameters theType =
    case theType of
        TypeParameter parameter -> [parameter]
        TypeOpaque (_, t) -> List.map getParameters t |> List.concat
        TypeUnion variants ->
            variants
            |> List.map ((\(_, t) -> List.map getParameters t) >> List.concat)
            |> List.concat
            
        TypeList t -> getParameters t
        TypeDict (_ , t)-> getParameters t
        TypeArray t -> getParameters t
        TypeBool -> []
        TypeError _ -> []
        TypeExtendedRecord t -> List.map (.theType >> getParameters) t |> List.concat
        TypeExtensible t -> List.map (.theType >> getParameters) t |> List.concat
        TypeFloat -> []
        TypeCustom _ parameter -> List.map getParameters parameter |> List.concat
        TypeInt -> []
        TypeMaybe a -> getParameters a
        TypeResult a b -> [getParameters a, getParameters b] |> List.concat
        TypeRecord fields -> List.map (.theType >> getParameters) fields |> List.concat
        TypeString -> []
        TypeTuple t -> List.map getParameters t |> List.concat

