%{
#include <stdio.h>
#include <stdlib.h> // Para malloc, free, atoi, sprintf
#include <string.h> // Para strdup, strcmp
#include <strings.h> // Para strcasecmp (en sistemas POSIX)
#include "types.h"
#include <sqlite3.h>


// Prototipo de la función del analizador léxico (generada por Flex)
int yylex();
// Prototipo de la función para reportar errores sintácticos
void yyerror(const char *s);

// Variables externas
extern int current_line; // Desde Flex, para el número de línea
extern char *yytext;     // Desde Flex, para el lexema actual
extern FILE *yyin;       // Desde Flex, para el flujo de entrada

// Variables globales para la base de datos
sqlite3 *db;
char *db_error_message = 0;



Value crear_valor_desde_cadena(char* sval_from_lexer);
Value crear_valor_desde_entero(int ival_from_lexer);
Value crear_valor_desde_booleano_texto(char* bool_text_from_lexer);

NodeAsignacion* crear_nodo_lista_asignacion(Asignacion asign_data);
NodeAsignacion* agregar_asignacion_a_lista(NodeAsignacion* lista_existente, Asignacion nueva_asign_data);
void liberar_valor_data(Value val_data);
void liberar_lista_asignaciones(NodeAsignacion* cabeza_lista);
void procesar_sentencia_insercion(char* nombre_tabla, NodeAsignacion* lista_de_asignaciones);

%}

%union {
    char *str_val;                  // Para IDENTIFICADOR, LITERAL_CADENA, KW_TRUE, KW_FALSE
    int int_val;                    // Para LITERAL_NUMERO

    Value valor_struct;             // Para el no-terminal <valor>
    Asignacion asignacion_struct;   // Para el no-terminal <asignacion>
    NodeAsignacion *lista_asig_ptr; // Para <lista_asignaciones> y <clausula_valores>
}


%token KW_INSERTAR KW_EN KW_TABLA KW_VALORES KW_FIN

%token <str_val> IDENTIFICADOR
%token <str_val> LITERAL_CADENA
%token <str_val> KW_TRUE           // El lexer pasa "true" como cadena
%token <str_val> KW_FALSE          // El lexer pasa "false" como cadena

%token <int_val> LITERAL_NUMERO

%token OP_IGUAL SYM_DOSPUNTOS SYM_COMA SYM_PUNTOYCOMA


%type <valor_struct> valor
%type <asignacion_struct> asignacion
%type <lista_asig_ptr> lista_asignaciones clausula_valores


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
        procesar_sentencia_insercion($4, $5);
    }
    ;

clausula_valores:
    KW_VALORES SYM_DOSPUNTOS lista_asignaciones
    {
        $$ = $3;
    }
    ;

lista_asignaciones:
    asignacion
    {
        $$ = crear_nodo_lista_asignacion($1);
        if (!$$) {
            yyerror("Fallo de memoria para nodo de asignacion en lista_asignaciones (1)");
            YYABORT;
        }
    }
    | lista_asignaciones SYM_COMA asignacion
    {
        $$ = agregar_asignacion_a_lista($1, $3);
         if (!$$) { // agregar_asignacion_a_lista puede fallar si crear_nodo_lista_asignacion falla dentro
            yyerror("Fallo de memoria para nodo de asignacion en lista_asignaciones (2)");
            YYABORT;
        }
    }
    ;

asignacion:
    IDENTIFICADOR OP_IGUAL valor
    {
        $$.campo = $1;
        $$.valor_data = $3;
    }
    ;

valor:
    LITERAL_CADENA
    {
        $$ = crear_valor_desde_cadena($1);
    }
    | LITERAL_NUMERO
    {
        $$ = crear_valor_desde_entero($1);
    }
    | KW_TRUE
    {
        $$ = crear_valor_desde_booleano_texto($1);
    }
    | KW_FALSE
    {
        $$ = crear_valor_desde_booleano_texto($1);
    }
    ;

%%


void yyerror(const char *s) {
    fprintf(stderr, "Error Sintáctico: %s en la línea %d, cerca de '%s'.\n", s, current_line, yytext);
}

Value crear_valor_desde_cadena(char* sval_from_lexer) {
    Value v;
    v.type = V_STR;
    v.val.sVal = sval_from_lexer;
    v.original_text = v.val.sVal; // Apunta al mismo string strdup'd por el lexer
    return v;
}

Value crear_valor_desde_entero(int ival_from_lexer) {
    Value v;
    v.type = V_INT;
    v.val.iVal = ival_from_lexer;
    char buffer[50];
    sprintf(buffer, "%d", ival_from_lexer);
    v.original_text = strdup(buffer);
    return v;
}

Value crear_valor_desde_booleano_texto(char* bool_text_from_lexer) {
    Value v;
    v.type = V_BOOL;
    v.original_text = bool_text_from_lexer; // Toma posesión del string del lexer
    if (strcasecmp(bool_text_from_lexer, "true") == 0) {
        v.val.iVal = 1;
    } else {
        v.val.iVal = 0;
    }
    return v;
}

NodeAsignacion* crear_nodo_lista_asignacion(Asignacion asign_data) {
    NodeAsignacion* nuevo_nodo = (NodeAsignacion*)malloc(sizeof(NodeAsignacion));
    if (!nuevo_nodo) {
        // yyerror("Fallo de memoria creando nodo de asignación"); // El error se reporta en la regla
        return NULL;
    }
    nuevo_nodo->data = asign_data;
    nuevo_nodo->next = NULL;
    return nuevo_nodo;
}

NodeAsignacion* agregar_asignacion_a_lista(NodeAsignacion* lista_existente, Asignacion nueva_asign_data) {
    NodeAsignacion* nuevo_nodo_asignacion = crear_nodo_lista_asignacion(nueva_asign_data);
    if (!nuevo_nodo_asignacion) { 
        return lista_existente; 
    }

    if (!lista_existente) {
        return nuevo_nodo_asignacion;
    }
    NodeAsignacion* temp = lista_existente;
    while (temp->next != NULL) {
        temp = temp->next;
    }
    temp->next = nuevo_nodo_asignacion;
    return lista_existente;
}

void liberar_valor_data(Value val_data) {
    if (val_data.original_text) {
        free(val_data.original_text); 
    }
}

void liberar_lista_asignaciones(NodeAsignacion* cabeza_lista) {
    NodeAsignacion* actual = cabeza_lista;
    NodeAsignacion* siguiente;
    while (actual != NULL) {
        siguiente = actual->next;
        if (actual->data.campo) {
            free(actual->data.campo);
        }
        liberar_valor_data(actual->data.valor_data);
        free(actual);
        actual = siguiente;
    }
}

void procesar_sentencia_insercion(char* nombre_tabla, NodeAsignacion* lista_de_asignaciones) {
    printf("ACCION_DB: Preparando inserción para la tabla -> '%s'\n", nombre_tabla);

    if (!lista_de_asignaciones) {
        fprintf(stderr, "Error: No hay asignaciones para insertar en la tabla '%s'.\n", nombre_tabla);
        if (nombre_tabla) free(nombre_tabla);
        return;
    }

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

    char sql_campos[1024] = "";
    char sql_placeholders[256] = "";
    
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

    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(db, sql_query, -1, &stmt, NULL);

    if (rc != SQLITE_OK) {
        fprintf(stderr, "Error al preparar la sentencia SQL (%s): %s\n", sql_query, sqlite3_errmsg(db));
    } else {
        temp = lista_de_asignaciones;
        for (int i = 0; i < num_asignaciones; i++) {
            int placeholder_idx = i + 1;
            Value v = temp->data.valor_data;
            switch (v.type) {
                case V_STR:
                    rc = sqlite3_bind_text(stmt, placeholder_idx, v.val.sVal, -1, SQLITE_STATIC);
                    break;
                case V_INT:
                    rc = sqlite3_bind_int(stmt, placeholder_idx, v.val.iVal);
                    break;
                case V_BOOL:
                    rc = sqlite3_bind_int(stmt, placeholder_idx, v.val.iVal);
                    break;
                default:
                    fprintf(stderr, "Error: Tipo de valor desconocido para el campo '%s'.\n", temp->data.campo);
                    rc = SQLITE_ERROR;
                    break;
            }
            if (rc != SQLITE_OK) {
                fprintf(stderr, "Error al vincular el valor para el campo '%s' (placeholder %d): %s\n", 
                        temp->data.campo, placeholder_idx, sqlite3_errmsg(db));
                break;
            }
            temp = temp->next;
        }

        if (rc == SQLITE_OK) {
            rc = sqlite3_step(stmt);
            if (rc == SQLITE_DONE) {
                printf("Inserción exitosa en la tabla '%s'.\n", nombre_tabla);
            } else {
                fprintf(stderr, "Error al ejecutar la inserción en '%s': %s\n", nombre_tabla, sqlite3_errmsg(db));
            }
        }
    }

    sqlite3_finalize(stmt);

    if (nombre_tabla) {
        free(nombre_tabla);
    }
    liberar_lista_asignaciones(lista_de_asignaciones);
}

int main(int argc, char *argv[]) {
    int rc_db;

    rc_db = sqlite3_open("mi_base_de_datos.db", &db);
    if (rc_db) {
        fprintf(stderr, "No se puede abrir la base de datos: %s\n", sqlite3_errmsg(db));
        sqlite3_close(db);
        return(1);
    } else {
        fprintf(stdout, "Base de datos abierta/creada exitosamente.\n");
    }

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
    
    char *sql_create_ordenes =
        "CREATE TABLE IF NOT EXISTS Ordenes ("
        "ID_Orden    TEXT PRIMARY KEY,"
        "ID_Usuario  TEXT NOT NULL,"
        "Fecha       TEXT NOT NULL,"
        "Total       INTEGER,"
        "FOREIGN KEY (ID_Usuario) REFERENCES Usuarios(ID_Usuario)"
        ");";

    
    rc_db = sqlite3_exec(db, sql_create_usuarios, 0, 0, &db_error_message);
    if (rc_db != SQLITE_OK) {
        fprintf(stderr, "Error SQL al crear tabla Usuarios: %s\n", db_error_message);
        sqlite3_free(db_error_message); 
        db_error_message = 0; 
    } else {
        fprintf(stdout, "Tabla Usuarios verificada/creada.\n");
    }

    rc_db = sqlite3_exec(db, sql_create_productos, 0, 0, &db_error_message);
    if (rc_db != SQLITE_OK) {
        fprintf(stderr, "Error SQL al crear tabla Productos: %s\n", db_error_message);
        sqlite3_free(db_error_message);
        db_error_message = 0;
    } else {
        fprintf(stdout, "Tabla Productos verificada/creada.\n");
    }

    rc_db = sqlite3_exec(db, sql_create_ordenes, 0, 0, &db_error_message);
    if (rc_db != SQLITE_OK) {
        fprintf(stderr, "Error SQL al crear tabla Ordenes: %s\n", db_error_message);
        sqlite3_free(db_error_message);
        db_error_message = 0;
    } else {
        fprintf(stdout, "Tabla Ordenes verificada/creada.\n");
    }


    if (argc > 1) {
        yyin = fopen(argv[1], "r");
        if (!yyin) {
            fprintf(stderr, "No se pudo abrir el archivo de entrada: %s\n", argv[1]);
            sqlite3_close(db);
            return 1;
        }
    }

    yyparse();

    sqlite3_close(db);
    return 0;
}

