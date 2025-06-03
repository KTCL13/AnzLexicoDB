%{
#include <stdio.h>
#include <stdlib.h> // Para malloc, free, atoi, sprintf
#include <string.h> // Para strdup, strcmp
#include <sqlite3.h>

// Prototipo de la función del analizador léxico (generada por Flex)
int yylex();
// Prototipo de la función para reportar errores sintácticos
void yyerror(const char *s);

// Variable externa para el número de línea (definida en el archivo .l de Flex)
// Asegúrate de que 'current_line' sea el nombre que usaste en tu archivo Flex.
// Si usaste %option yylineno en Flex, entonces deberías usar 'extern int yylineno;'.
extern int current_line;

sqlite3 *   
char *db_error_message = 0;

// --- Definición de Estructuras de Datos para las Asignaciones ---

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
        int   iVal; // Usado para V_INT
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


// --- Prototipos de Funciones Auxiliares (implementadas más abajo) ---
Value crear_valor_desde_cadena(char* sval_from_lexer);
Value crear_valor_desde_entero(int ival_from_lexer);
Value crear_valor_desde_booleano_texto(char* bool_text_from_lexer);

NodeAsignacion* crear_nodo_lista_asignacion(Asignacion asign_data);
NodeAsignacion* agregar_asignacion_a_lista(NodeAsignacion* lista_existente, Asignacion nueva_asign_data);
void liberar_valor_data(Value val_data);
void liberar_lista_asignaciones(NodeAsignacion* cabeza_lista);
void procesar_sentencia_insercion(char* nombre_tabla, NodeAsignacion* lista_de_asignaciones);

%}

/* Definición de la unión de tipos para yylval */
%union {
    char *str_val;                  // Para IDENTIFICADOR, LITERAL_CADENA, KW_TRUE, KW_FALSE
    int int_val;                    // Para LITERAL_NUMERO
    
    Value valor_struct;             // Para el no-terminal <valor>
    Asignacion asignacion_struct;   // Para el no-terminal <asignacion>
    NodeAsignacion *lista_asig_ptr; // Para <lista_asignaciones> y <clausula_valores>
}

/* Declaración de Tokens (Símbolos Terminales) */
// Palabras clave sin valor semántico directo (solo su tipo es importante)
%token KW_INSERTAR KW_EN KW_TABLA KW_VALORES KW_FIN

// Tokens que llevan un valor de cadena (str_val)
%token <str_val> IDENTIFICADOR
%token <str_val> LITERAL_CADENA
%token <str_val> KW_TRUE           // El lexer pasa "true" como cadena
%token <str_val> KW_FALSE          // El lexer pasa "false" como cadena

// Token que lleva un valor entero (int_val)
%token <int_val> LITERAL_NUMERO

// Operadores y símbolos de puntuación (sin valor semántico directo)
%token OP_IGUAL SYM_DOSPUNTOS SYM_COMA SYM_PUNTOYCOMA

/* Tipos para Símbolos No Terminales que devuelven un valor */
%type <valor_struct> valor
%type <asignacion_struct> asignacion
%type <lista_asig_ptr> lista_asignaciones clausula_valores

/* Símbolo Inicial de la Gramática */
%start programa

%%

/* Reglas de la Gramática con Acciones Semánticas */

programa:
    /* Un programa puede estar vacío */
    | lista_sentencias
    ;

lista_sentencias:
    sentencia_insercion
    | lista_sentencias sentencia_insercion /* Permite múltiples sentencias */
    ;

sentencia_insercion:
    KW_INSERTAR KW_EN KW_TABLA IDENTIFICADOR clausula_valores KW_FIN SYM_PUNTOYCOMA
    {
        // $4 es IDENTIFICADOR (nombre_tabla) -> yylval.str_val
        // $5 es clausula_valores -> yylval.lista_asig_ptr
        procesar_sentencia_insercion($4, $5); 
        // La función procesar_sentencia_insercion se encargará de liberar la memoria de $4 y $5.
    }
    ;

clausula_valores:
    KW_VALORES SYM_DOSPUNTOS lista_asignaciones
    {
        $$ = $3; // Pasa el puntero a la lista de asignaciones hacia arriba
    }
    ;

lista_asignaciones:
    asignacion
    {
        // Crea una nueva lista que contiene la única asignación ($1)
        $$ = crear_nodo_lista_asignacion($1);
    }
    | lista_asignaciones SYM_COMA asignacion
    {
        // Agrega la nueva asignación ($3) a la lista existente ($1)
        $$ = agregar_asignacion_a_lista($1, $3);
    }
    ;

asignacion:
    IDENTIFICADOR OP_IGUAL valor
    {
        // $1 es IDENTIFICADOR (nombre_campo) -> yylval.str_val
        // $3 es valor -> yylval.valor_struct
        $$.campo = $1;       // strdup'd en el lexer, $$.campo toma posesión
        $$.valor_data = $3;  // $$.valor_data toma posesión de los contenidos de $3
    }
    ;

valor:
    LITERAL_CADENA  // yylval.str_val (ya sin comillas desde el lexer)
    {
        $$ = crear_valor_desde_cadena($1); 
        // $1 es strdup'd en el lexer. crear_valor_desde_cadena toma posesión.
    }
    | LITERAL_NUMERO  // yylval.int_val
    {
        $$ = crear_valor_desde_entero($1);
    }
    | KW_TRUE         // yylval.str_val (ej. "true")
    {
        $$ = crear_valor_desde_booleano_texto($1);
        // $1 es strdup'd en el lexer. crear_valor_desde_booleano_texto toma posesión.
    }
    | KW_FALSE        // yylval.str_val (ej. "false")
    {
        $$ = crear_valor_desde_booleano_texto($1);
        // $1 es strdup'd en el lexer. crear_valor_desde_booleano_texto toma posesión.
    }
    ;

%%

/* Sección de Código C Adicional (User Code Section) */

// Función para reportar errores sintácticos
void yyerror(const char *s) {
    // 'yytext' contiene el token que causó el error (si está disponible)
    // 'current_line' es nuestra variable global del lexer
    fprintf(stderr, "Error Sintáctico: %s en la línea %d, cerca de '%s'.\n", s, current_line, yytext);
}


// --- Implementación de Funciones Auxiliares ---

Value crear_valor_desde_cadena(char* sval_from_lexer) {
    Value v;
    v.type = V_STR;
    v.val.sVal = sval_from_lexer; // Toma posesión del strdup'd string del lexer
    v.original_text = v.val.sVal; // Apunta al mismo string
    return v;
}

Value crear_valor_desde_entero(int ival_from_lexer) {
    Value v;
    v.type = V_INT;
    v.val.iVal = ival_from_lexer;
    char buffer[50]; // Suficiente para un entero
    sprintf(buffer, "%d", ival_from_lexer);
    v.original_text = strdup(buffer); // Creamos una representación en cadena
    return v;
}

Value crear_valor_desde_booleano_texto(char* bool_text_from_lexer) {
    Value v;
    v.type = V_BOOL;
    v.original_text = bool_text_from_lexer; // Toma posesión
    // Convertir "true"/"false" a 1/0. strcasecmp es POSIX.
    // Para portabilidad total, podrías convertir bool_text_from_lexer a minúsculas primero.
    if (strcasecmp(bool_text_from_lexer, "true") == 0) {
        v.val.iVal = 1;
    } else {
        v.val.iVal = 0; // Asume que cualquier cosa que no sea "true" es false
    }
    return v;
}

NodeAsignacion* crear_nodo_lista_asignacion(Asignacion asign_data) {
    NodeAsignacion* nuevo_nodo = (NodeAsignacion*)malloc(sizeof(NodeAsignacion));
    if (!nuevo_nodo) {
        yyerror("Fallo de memoria creando nodo de asignación");
        YYABORT; // Termina el parsing
    }
    nuevo_nodo->data = asign_data; // Copia la estructura Asignacion
    nuevo_nodo->next = NULL;
    return nuevo_nodo;
}

NodeAsignacion* agregar_asignacion_a_lista(NodeAsignacion* lista_existente, Asignacion nueva_asign_data) {
    NodeAsignacion* nuevo_nodo_asignacion = crear_nodo_lista_asignacion(nueva_asign_data);
    if (!lista_existente) {
        return nuevo_nodo_asignacion; // La nueva asignación es la cabeza de la lista
    }
    NodeAsignacion* temp = lista_existente;
    while (temp->next != NULL) {
        temp = temp->next;
    }
    temp->next = nuevo_nodo_asignacion;
    return lista_existente; // Devuelve la cabeza original de la lista
}

void liberar_valor_data(Value val_data) {
    // original_text siempre es un strdup'd (o tomado del lexer que hizo strdup)
    if (val_data.original_text) {
        free(val_data.original_text);
    }
    // Si val.sVal fuera un strdup diferente de original_text, también se liberaría aquí.
    // En este diseño, para V_STR, val.sVal y original_text apuntan al mismo string.
}

void liberar_lista_asignaciones(NodeAsignacion* cabeza_lista) {
    NodeAsignacion* actual = cabeza_lista;
    NodeAsignacion* siguiente;
    while (actual != NULL) {
        siguiente = actual->next;
        // Liberar memoria dentro de Asignacion
        if (actual->data.campo) {
            free(actual->data.campo); // strdup'd por el lexer para IDENTIFICADOR
        }
        liberar_valor_data(actual->data.valor_data);
        
        // Liberar el nodo mismo
        free(actual);
        actual = siguiente;
    }
}

// En la sección de código C de tu archivo .y
void procesar_sentencia_insercion(char* nombre_tabla, NodeAsignacion* lista_de_asignaciones) {
    printf("ACCION_DB: Preparando inserción para la tabla -> '%s'\n", nombre_tabla);

    if (!lista_de_asignaciones) {
        fprintf(stderr, "Error: No hay asignaciones para insertar en la tabla '%s'.\n", nombre_tabla);
        if (nombre_tabla) free(nombre_tabla);
        return;
    }

    // 1. Contar asignaciones y construir listas de campos y placeholders
    int num_asignaciones = 0;
    NodeAsignacion* temp = lista_de_asignaciones;
    while (temp != NULL) {
        num_asignaciones++;
        temp = temp->next;
    }

    if (num_asignaciones == 0) {
         fprintf(stderr, "Error: Lista de asignaciones vacía para tabla '%s'.\n", nombre_tabla);
        if (nombre_tabla) free(nombre_tabla);
        liberar_lista_asignaciones(lista_de_asignaciones);
        return;
    }

    // Buffers para construir la query. Asegúrate de que sean suficientemente grandes
    // o usa asignación dinámica de memoria.
    char sql_campos[1024] = ""; // Para "campo1, campo2, ..."
    char sql_placeholders[256] = ""; // Para "?, ?, ..."
    
    temp = lista_de_asignaciones;
    for (int i = 0; i < num_asignaciones; i++) {
        strcat(sql_campos, temp->data.campo);
        strcat(sql_placeholders, "?");
        if (i < num_asignaciones - 1) {
            strcat(sql_campos, ", ");
            strcat(sql_placeholders, ", ");
        }
        temp = temp->next;
    }

    char sql_query[2048];
    sprintf(sql_query, "INSERT INTO %s (%s) VALUES (%s);", 
            nombre_tabla, sql_campos, sql_placeholders);

    printf("SQL Query: %s\n", sql_query);

    // 2. Preparar la sentencia SQL
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(db, sql_query, -1, &stmt, NULL);

    if (rc != SQLITE_OK) {
        fprintf(stderr, "Error al preparar la sentencia SQL (%s): %s\n", sql_query, sqlite3_errmsg(db));
    } else {
        // 3. Vincular los valores a los placeholders
        temp = lista_de_asignaciones;
        for (int i = 0; i < num_asignaciones; i++) {
            int placeholder_idx = i + 1; // Los placeholders en SQL son 1-indexados
            Value v = temp->data.valor_data;
            switch (v.type) {
                case V_STR:
                    rc = sqlite3_bind_text(stmt, placeholder_idx, v.val.sVal, -1, SQLITE_STATIC);
                    // SQLITE_STATIC asume que el string v.val.sVal existirá hasta después de sqlite3_step.
                    // Si no, usa SQLITE_TRANSIENT y SQLite hará su propia copia.
                    break;
                case V_INT:
                    rc = sqlite3_bind_int(stmt, placeholder_idx, v.val.iVal);
                    break;
                case V_BOOL: // Asumiendo que lo almacenamos como entero 0 o 1
                    rc = sqlite3_bind_int(stmt, placeholder_idx, v.val.iVal);
                    break;
                default:
                    fprintf(stderr, "Error: Tipo de valor desconocido para el campo '%s'.\n", temp->data.campo);
                    rc = SQLITE_ERROR; // Marcar como error para no ejecutar
                    break;
            }
            if (rc != SQLITE_OK) {
                fprintf(stderr, "Error al vincular el valor para el campo '%s' (placeholder %d): %s\n", 
                        temp->data.campo, placeholder_idx, sqlite3_errmsg(db));
                break; // Salir del bucle de vinculación
            }
            temp = temp->next;
        }

        // 4. Ejecutar la sentencia (si la vinculación fue exitosa)
        if (rc == SQLITE_OK) {
            rc = sqlite3_step(stmt);
            if (rc == SQLITE_DONE) {
                printf("Inserción exitosa en la tabla '%s'.\n", nombre_tabla);
            } else {
                fprintf(stderr, "Error al ejecutar la inserción en '%s': %s\n", nombre_tabla, sqlite3_errmsg(db));
            }
        }
    }

    // 5. Finalizar la sentencia para liberar recursos
    sqlite3_finalize(stmt);

    // --- Liberación de Memoria ---
    if (nombre_tabla) {
        free(nombre_tabla);
    }
    liberar_lista_asignaciones(lista_de_asignaciones);
}


// Función principal que inicia el análisis
int main(int argc, char *argv[]) {
    int rc_db; // Código de retorno para operaciones de BD

    // Abrir la base de datos
    rc_db = sqlite3_open("mi_base_de_datos.db", &db); // Intenta abrir/crear el archivo
    if (rc_db) {
        fprintf(stderr, "No se puede abrir la base de datos: %s\n", sqlite3_errmsg(db));
        sqlite3_close(db); // Aunque falle, intenta cerrar
        return(1);
    } else {
        fprintf(stdout, "Base de datos abierta/creada exitosamente.\n");
    }

// ... dentro de main(), después de sqlite3_open() ...
    char *sql_create_usuarios = 
        "CREATE TABLE IF NOT EXISTS Usuarios ("
        "ID_Usuario TEXT PRIMARY KEY,"
        "Nombre     TEXT NOT NULL,"
        "Email      TEXT UNIQUE,"
        "Activo     INTEGER DEFAULT 0" 
        ");";

    char *sql_create_productos =
        "CREATE TABLE IF NOT EXISTS Productos ("
        "SKU             TEXT PRIMARY KEY,"
        "NombreProducto  TEXT NOT NULL,"
        "Stock           INTEGER,"
        "Precio          INTEGER,"
        "Disponible      INTEGER DEFAULT 0"
        ");";
    
    // Ejecutar las sentencias CREATE TABLE
    rc_db = sqlite3_exec(db, sql_create_usuarios, 0, 0, &db_error_message);
    if (rc_db != SQLITE_OK) {
        fprintf(stderr, "Error SQL al crear tabla Usuarios: %s\n", db_error_message);
        sqlite3_free(db_error_message);
    } else {
        fprintf(stdout, "Tabla Usuarios verificada/creada.\n");
    }

    rc_db = sqlite3_exec(db, sql_create_productos, 0, 0, &db_error_message);
    if (rc_db != SQLITE_OK) {
        fprintf(stderr, "Error SQL al crear tabla Productos: %s\n", db_error_message);
        sqlite3_free(db_error_message);
    } else {
        fprintf(stdout, "Tabla Productos verificada/creada.\n");
    }
// ... resto del main() ...

    // Configurar la entrada (desde archivo o stdin)
    if (argc > 1) {
        yyin = fopen(argv[1], "r");
        if (!yyin) {
            perror(argv[1]);
            sqlite3_close(db);
            return 1;
        }
    } else {
        yyin = stdin;
        printf("Leyendo desde la entrada estándar...\n");
    }

    int resultado_parse = yyparse();

    if (yyin != stdin && yyin != NULL) {
        fclose(yyin);
    }

    sqlite3_close(db); // <--- ¡NUEVO! Cerrar la base de datos al final

    if (resultado_parse == 0) {
        printf("Análisis completado exitosamente.\n");
        return 0;
    } else {
        printf("Análisis fallido.\n");
        return 1;
    }
}