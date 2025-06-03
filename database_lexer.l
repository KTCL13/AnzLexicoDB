%{
#include <stdio.h>
#include <stdlib.h> // Para atoi()
#include <string.h> // Para strdup() y strlen()

// Incluir el archivo de cabecera generado por Bison.
// Este archivo contiene las definiciones de los tokens (ej. KW_INSERTAR)
// y la declaración de yylval (si se usa %union en Bison).
#include "database_parser.tab.h"

// Contador de líneas para reportar errores con precisión.
// Alternativamente, se puede usar %option yylineno para que Flex lo maneje.
int current_line = 1;

// Prototipo de la función de error del parser (Bison)
// void yyerror(const char *s); 
// Si se prueba el lexer de forma aislada, se puede definir una versión simple aquí.
%}

/* Opciones de Flex */
%option noyywrap          /* No llamar a yywrap() al final del archivo */
%option case-insensitive  /* Palabras clave y booleanos no distinguen mayúsculas/minúsculas */
/* %option yylineno */    /* Descomentar si se prefiere que Flex maneje el número de línea en 'yylineno' */


/* Definiciones de Expresiones Regulares (Macros) */
DIGITO                [0-9]
LETRA                 [a-zA-Z_]
IDENTIFICADOR         {LETRA}({LETRA}|{DIGITO})*
NUMERO                {DIGITO}+
CADENA                '[^'\n]*' /* Cadenas entre comillas simples, no pueden contener saltos de línea ni comillas simples internas (sin escape) */
COMENTARIO            --[^\n]*

%%

/* Reglas para Palabras Reservadas y Booleanos */
"insertar"      { /*printf("LEX: KW_INSERTAR ('%s') en línea %d\n", yytext, current_line);*/ return KW_INSERTAR; }
"en"            { /*printf("LEX: KW_EN ('%s') en línea %d\n", yytext, current_line);*/ return KW_EN; }
"tabla"         { /*printf("LEX: KW_TABLA ('%s') en línea %d\n", yytext, current_line);*/ return KW_TABLA; }
"valores"       { /*printf("LEX: KW_VALORES ('%s') en línea %d\n", yytext, current_line);*/ return KW_VALORES; }
"fin"           { /*printf("LEX: KW_FIN ('%s') en línea %d\n", yytext, current_line);*/ return KW_FIN; }

"true"          { 
                  /*printf("LEX: KW_TRUE ('%s') en línea %d\n", yytext, current_line);*/
                  yylval.str_val = strdup(yytext); // Guardar "true" como cadena
                  return KW_TRUE; 
                }
"false"         { 
                  /*printf("LEX: KW_FALSE ('%s') en línea %d\n", yytext, current_line);*/
                  yylval.str_val = strdup(yytext); // Guardar "false" como cadena
                  return KW_FALSE; 
                }

/* Reglas para Identificadores, Literales Numéricos y de Cadena */
{IDENTIFICADOR}  {
                        /*printf("LEX: IDENTIFICADOR ('%s') en línea %d\n", yytext, current_line);*/
                        yylval.str_val = strdup(yytext); // Copiar el identificador
                        return IDENTIFICADOR;
                      }

{NUMERO}        {
                        /*printf("LEX: LITERAL_NUMERO ('%s') en línea %d\n", yytext, current_line);*/
                        yylval.int_val = atoi(yytext); // Convertir a entero
                        return LITERAL_NUMERO;
                      }

{CADENA}        {
                        /*printf("LEX: LITERAL_CADENA ('%s') en línea %d\n", yytext, current_line);*/
                        // Remover las comillas simples de los extremos antes de pasarla
                        char *unquoted_string = strdup(yytext + 1); 
                        unquoted_string[strlen(unquoted_string) - 1] = '\0'; // Eliminar la última comilla
                        yylval.str_val = unquoted_string;
                        return LITERAL_CADENA;
                      }

/* Reglas para Operadores y Símbolos de Puntuación */
"="                 { /*printf("LEX: OP_IGUAL ('=') en línea %d\n", current_line);*/ return OP_IGUAL; }
":"                 { /*printf("LEX: SYM_DOSPUNTOS (':') en línea %d\n", current_line);*/ return SYM_DOSPUNTOS; }
","                 { /*printf("LEX: SYM_COMA (',') en línea %d\n", current_line);*/ return SYM_COMA; }
";"                 { /*printf("LEX: SYM_PUNTOYCOMA (';') en línea %d\n", current_line);*/ return SYM_PUNTOYCOMA; }


/* Reglas para Ignorar Comentarios y Espacios en Blanco */
{COMENTARIO_REGEX}    { /*printf("LEX: COMENTARIO ('%s') en línea %d - Ignorado\n", yytext, current_line);*/ /* Ignorar */ }

[ \t]+              { /* Ignorar espacios en blanco y tabuladores */ }

\n                  { current_line++; /* Incrementar contador de línea (si no se usa yylineno) */ }


/* Regla para Caracteres Desconocidos (Error Léxico) */
.                   { 
                      fprintf(stderr, "Error Léxico: Carácter desconocido '%s' en la línea %d.\n", yytext, current_line);
                      // Podría devolverse un token de error específico si el parser está preparado para manejarlo.
                      // return LEXICAL_ERROR_TOKEN; 
                    }

%%