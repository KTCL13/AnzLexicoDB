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
%option noyywrap          
%option case-insensitive  



/* Definiciones de Expresiones Regulares (Macros) */
DIGITO                [0-9]
LETRA                 [a-zA-Z_]
IDENTIFICADOR         {LETRA}({LETRA}|{DIGITO})*
NUMERO                {DIGITO}+
CADENA                '[^'\n]*'  
COMENTARIO            --[^\n]*

%%


"insertar"      {  return KW_INSERTAR; }
"en"            {  return KW_EN; }
"tabla"         {  return KW_TABLA; }
"valores"       {  return KW_VALORES; }
"fin"           {  return KW_FIN; }

"true"          { 
                  printf("LEX: KW_TRUE ('%s') en línea %d\n", yytext, current_line);
                  yylval.str_val = strdup(yytext); // Guardar "true" como cadena
                  return KW_TRUE; 
                }
"false"         { 
                  printf("LEX: KW_FALSE ('%s') en línea %d\n", yytext, current_line);
                  yylval.str_val = strdup(yytext); // Guardar "false" como cadena
                  return KW_FALSE; 
                }

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

"="                 { /*printf("LEX: OP_IGUAL ('=') en línea %d\n", current_line);*/ return OP_IGUAL; }
":"                 { /*printf("LEX: SYM_DOSPUNTOS (':') en línea %d\n", current_line);*/ return SYM_DOSPUNTOS; }
","                 { /*printf("LEX: SYM_COMA (',') en línea %d\n", current_line);*/ return SYM_COMA; }
";"                 { /*printf("LEX: SYM_PUNTOYCOMA (';') en línea %d\n", current_line);*/ return SYM_PUNTOYCOMA; }



{COMENTARIO}    { /*printf("LEX: COMENTARIO ('%s') en línea %d - Ignorado\n", yytext, current_line);*/ /* Ignorar */ }

[ \t]+              { /* Ignorar espacios en blanco y tabuladores */ }

\n                  { current_line++; /* Incrementar contador de línea (si no se usa yylineno) */ }


.                   { 
                      fprintf(stderr, "Error Léxico: Carácter desconocido '%s' en la línea %d.\n", yytext, current_line);
        
                    }

%%