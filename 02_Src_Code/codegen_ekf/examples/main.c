/*
 * File: main.c
 *
 * MATLAB Coder version            : 25.1
 * C/C++ source code generated on  : 2026-06-05 15:20:07
 */

/*************************************************************************/
/* This automatically generated example C main file shows how to call    */
/* entry-point functions that MATLAB Coder generated. You must customize */
/* this file for your application. Do not modify this file directly.     */
/* Instead, make a copy of this file, modify it, and integrate it into   */
/* your development environment.                                         */
/*                                                                       */
/* This file initializes entry-point function arguments to a default     */
/* size and value before calling the entry-point functions. It does      */
/* not store or use any values returned from the entry-point functions.  */
/* If necessary, it does pre-allocate memory for returned values.        */
/* You can use this file as a starting point for a main function that    */
/* you can deploy in your application.                                   */
/*                                                                       */
/* After you copy the file, and before you deploy it, you must make the  */
/* following changes:                                                    */
/* * For variable-size function arguments, change the example sizes to   */
/* the sizes that your application requires.                             */
/* * Change the example values of function arguments to the values that  */
/* your application requires.                                            */
/* * If the entry-point functions return values, store these values or   */
/* otherwise use them as required by your application.                   */
/*                                                                       */
/*************************************************************************/

/* Include Files */
#include "main.h"
#include "ekf_soc_step_cg.h"
#include "ekf_soc_step_cg_initialize.h"
#include "ekf_soc_step_cg_terminate.h"
#include "ekf_soc_step_cg_types.h"
#include <string.h>

/* Function Declarations */
static void argInit_21x1_real_T(double result[21]);

static void argInit_2x2_real_T(double result[4]);

static bool argInit_boolean_T(void);

static double argInit_real_T(void);

static void argInit_struct0_T(struct0_T *result);

/* Function Definitions */
/*
 * Arguments    : double result[21]
 * Return Type  : void
 */
static void argInit_21x1_real_T(double result[21])
{
  int idx0;
  /* Loop over the array to initialize each element. */
  for (idx0 = 0; idx0 < 21; idx0++) {
    /* Set the value of the array element.
Change this value to the value that the application requires. */
    result[idx0] = argInit_real_T();
  }
}

/*
 * Arguments    : double result[4]
 * Return Type  : void
 */
static void argInit_2x2_real_T(double result[4])
{
  int i;
  /* Loop over the array to initialize each element. */
  for (i = 0; i < 4; i++) {
    /* Set the value of the array element.
Change this value to the value that the application requires. */
    result[i] = argInit_real_T();
  }
}

/*
 * Arguments    : void
 * Return Type  : bool
 */
static bool argInit_boolean_T(void)
{
  return false;
}

/*
 * Arguments    : void
 * Return Type  : double
 */
static double argInit_real_T(void)
{
  return 0.0;
}

/*
 * Arguments    : struct0_T *result
 * Return Type  : void
 */
static void argInit_struct0_T(struct0_T *result)
{
  double result_tmp;
  /* Set the value of each structure field.
Change this value to the value that the application requires. */
  result_tmp = argInit_real_T();
  argInit_21x1_real_T(result->SOC_bp);
  argInit_2x2_real_T(result->Q);
  result->R0_Ohm = result_tmp;
  result->R1_Ohm = result_tmp;
  result->C1_F = result_tmp;
  result->Cap_Ah = result_tmp;
  result->soc0 = result_tmp;
  result->R = result_tmp;
  memcpy(&result->OCV_bp[0], &result->SOC_bp[0], 21U * sizeof(double));
  result->P0[0] = result->Q[0];
  result->P0[1] = result->Q[1];
  result->P0[2] = result->Q[2];
  result->P0[3] = result->Q[3];
}

/*
 * Arguments    : int argc
 *                char **argv
 * Return Type  : int
 */
int main(int argc, char **argv)
{
  (void)argc;
  (void)argv;
  /* Initialize the application.
You do not need to do this more than one time. */
  ekf_soc_step_cg_initialize();
  /* Invoke the entry-point functions.
You can call entry-point functions multiple times. */
  main_ekf_soc_step_cg();
  /* Terminate the application.
You do not need to do this more than one time. */
  ekf_soc_step_cg_terminate();
  return 0;
}

/*
 * Arguments    : void
 * Return Type  : void
 */
void main_ekf_soc_step_cg(void)
{
  struct0_T r;
  double I_k_tmp;
  double soc;
  double vhat;
  double vrc;
  /* Initialize function 'ekf_soc_step_cg' input arguments. */
  I_k_tmp = argInit_real_T();
  /* Initialize function input argument 'prm'. */
  /* Call the entry-point 'ekf_soc_step_cg'. */
  argInit_struct0_T(&r);
  ekf_soc_step_cg(I_k_tmp, I_k_tmp, I_k_tmp, &r, argInit_boolean_T(), &soc,
                  &vrc, &vhat);
}

/*
 * File trailer for main.c
 *
 * [EOF]
 */
