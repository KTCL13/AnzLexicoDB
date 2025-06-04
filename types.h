// types.h
#ifndef TYPES_H
#define TYPES_H

// Enumeración para el tipo de valor
typedef enum ValType {
    V_STR,
    V_INT,
    V_BOOL
} ValType;

// Estructura para un valor, incluyendo su tipo y representación original
typedef struct Value {
    ValType type;
    union {
        char* sVal; // Usado para V_STR
        int   iVal; // Usado para V_INT (y V_BOOL convertido)
    } val;
    char* original_text; // Almacena el texto original del lexema (ej. "true", "123", "'abc'")
} Value;

// Estructura para una asignación (campo = valor)
typedef struct Asignacion {
    char *campo;      // Nombre del campo (identificador)
    Value valor_data; // El valor asignado con su tipo
} Asignacion;

// Nodo para la lista enlazada de asignaciones
typedef struct NodeAsignacion {
    Asignacion data;
    struct NodeAsignacion *next;
} NodeAsignacion;

#endif // TYPES_H                                           